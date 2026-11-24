@preconcurrency import AVFoundation

/// AVAudioEngine-based player: gapless (next file queued on the same node),
/// crossfade (two nodes with volume ramps), speed without pitch change, and a 10-band EQ.
///
/// Graph: [playerA, playerB] → mixer → timePitch → EQ → main mixer → output
@MainActor
final class AudioEnginePlayer {
    /// The current file played to its end and nothing was queued behind it.
    var onFinished: (() -> Void)?
    /// The gaplessly queued file has started playing.
    var onAdvancedToQueued: (() -> Void)?

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: EqualizerPreset.frequencies.count)
    private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private var activeIndex = 0
    private var active: AVAudioPlayerNode { players[activeIndex] }

    private var file: AVAudioFile?
    /// Frame the current file was scheduled from (after a seek).
    private var startFrame: AVAudioFramePosition = 0
    /// Frames of earlier files played on the active node since its last `play()` (gapless chain).
    private var frameOffset: AVAudioFramePosition = 0
    private var queuedFile: AVAudioFile?
    private(set) var queuedURL: URL?
    /// Bumped on every stop/seek/load so completion callbacks from old schedules are ignored.
    private var generation = 0
    private var pausedAt: Double?
    private var fadeTimer: Timer?

    init() {
        engine.attach(mixer)
        engine.attach(timePitch)
        engine.attach(eq)
        players.forEach(engine.attach)
        for player in players { engine.connect(player, to: mixer, format: nil) }
        engine.connect(mixer, to: timePitch, format: nil)
        engine.connect(timePitch, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        for (band, frequency) in zip(eq.bands, EqualizerPreset.frequencies) {
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
        engine.prepare()

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverFromConfigurationChange() }
        }
    }

    // MARK: - State

    var isPlaying: Bool { pausedAt == nil && file != nil && active.isPlaying }

    var duration: Double {
        guard let file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    var currentTime: Double {
        if let pausedAt { return pausedAt }
        guard let file else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        guard let nodeTime = active.lastRenderTime,
              let playerTime = active.playerTime(forNodeTime: nodeTime) else {
            return Double(startFrame) / sampleRate
        }
        let frames = playerTime.sampleTime - frameOffset + startFrame
        return min(max(Double(frames) / sampleRate, 0), duration)
    }

    // MARK: - Transport

    func load(_ url: URL, at position: Double, autoplay: Bool) throws {
        let newFile = try AVAudioFile(forReading: url)
        cancelFade()
        generation += 1
        players.forEach { $0.stop() }
        players.forEach { $0.volume = 1 }
        file = newFile
        queuedFile = nil
        queuedURL = nil
        engine.connect(active, to: mixer, format: newFile.processingFormat)
        try startEngineIfNeeded()
        schedule(from: position)
        if autoplay {
            active.play()
            pausedAt = nil
        } else {
            pausedAt = min(max(position, 0), duration)
        }
    }

    func play() {
        guard file != nil else { return }
        let resumeAt = pausedAt ?? currentTime
        if !engine.isRunning {
            do { try engine.start() } catch { return }
            // The engine was stopped (e.g. by an interruption), so rebuild the schedule from the saved spot.
            cancelFade()
            generation += 1
            players.forEach { $0.stop() }
            queuedFile = nil
            queuedURL = nil
            schedule(from: resumeAt)
        }
        active.play()
        pausedAt = nil
    }

    func pause() {
        guard file != nil else { return }
        pausedAt = currentTime
        finishFadeImmediately()
        active.pause()
    }

    func seek(to seconds: Double) {
        guard file != nil else { return }
        let wasPlaying = isPlaying
        let target = min(max(seconds, 0), max(duration - 0.05, 0))
        cancelFade()
        generation += 1
        active.stop()
        queuedFile = nil
        queuedURL = nil
        schedule(from: target)
        if wasPlaying {
            active.play()
            pausedAt = nil
        } else {
            pausedAt = target
        }
    }

    func stop() {
        cancelFade()
        generation += 1
        players.forEach { $0.stop() }
        file = nil
        queuedFile = nil
        queuedURL = nil
        pausedAt = nil
    }

    // MARK: - Gapless

    /// Queues `url` right behind the current file on the same node, so it starts with no gap.
    /// Only works when both files share a format; returns false otherwise (the caller falls back
    /// to starting the next track when this one finishes).
    @discardableResult
    func queueNext(_ url: URL) -> Bool {
        guard let file, queuedFile == nil,
              let next = try? AVAudioFile(forReading: url),
              next.processingFormat.sampleRate == file.processingFormat.sampleRate,
              next.processingFormat.channelCount == file.processingFormat.channelCount,
              next.length > 0 else { return false }
        queuedFile = next
        queuedURL = url
        let gen = generation
        active.scheduleSegment(next, startingFrame: 0, frameCount: AVAudioFrameCount(next.length), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.segmentFinished(next, generation: gen) }
        }
        return true
    }

    /// Drops a queued file (queue changed). Reschedules the current file from where it is.
    func clearQueued() {
        guard queuedFile != nil else { return }
        seek(to: currentTime)
    }

    // MARK: - Crossfade

    /// Starts `url` on the idle node and fades it in while fading the current one out.
    func crossfade(to url: URL, duration fade: Double) throws {
        let newFile = try AVAudioFile(forReading: url)
        cancelFade()
        generation += 1
        let outgoingIndex = activeIndex
        activeIndex = 1 - activeIndex
        let incomingIndex = activeIndex
        let incoming = active
        incoming.stop()
        engine.connect(incoming, to: mixer, format: newFile.processingFormat)
        file = newFile
        queuedFile = nil
        queuedURL = nil
        incoming.volume = 0
        schedule(from: 0)
        incoming.play()
        pausedAt = nil

        let steps = 30.0
        var step = 0.0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: max(fade, 0.1) / steps, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                step += 1
                let t = Float(min(step / steps, 1))
                // Equal-power curve keeps loudness steady through the fade.
                self.players[incomingIndex].volume = sin(t * .pi / 2)
                self.players[outgoingIndex].volume = cos(t * .pi / 2)
                if t >= 1 {
                    timer.invalidate()
                    self.players[outgoingIndex].stop()
                    self.players[outgoingIndex].volume = 1
                    self.fadeTimer = nil
                }
            }
        }
    }

    // MARK: - Effects

    var rate: Float {
        get { timePitch.rate }
        set { timePitch.rate = min(max(newValue, 0.5), 2.0) }
    }

    func setEQ(_ preset: EqualizerPreset) {
        let gains = preset.bandGains
        for (band, gain) in zip(eq.bands, gains) { band.gain = gain }
        // Headroom so boosted bands don't clip.
        eq.globalGain = -max(gains.max() ?? 0, 0) * 0.5
        eq.bypass = preset == .flat
    }

    // MARK: - Private

    private func schedule(from seconds: Double) {
        guard let file else { return }
        let sampleRate = file.processingFormat.sampleRate
        let frame = min(max(AVAudioFramePosition(seconds * sampleRate), 0), file.length)
        startFrame = frame
        frameOffset = 0
        let remaining = AVAudioFrameCount(max(file.length - frame, 0))
        let gen = generation
        guard remaining > 0 else {
            Task { @MainActor in self.segmentFinished(file, generation: gen) }
            return
        }
        active.scheduleSegment(file, startingFrame: frame, frameCount: remaining, at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.segmentFinished(file, generation: gen) }
        }
    }

    private func segmentFinished(_ finished: AVAudioFile, generation gen: Int) {
        guard gen == generation, finished === file else { return }
        if let queuedFile {
            // Gapless hand-off: the queued file is already playing on this node.
            frameOffset += finished.length - startFrame
            startFrame = 0
            file = queuedFile
            self.queuedFile = nil
            queuedURL = nil
            onAdvancedToQueued?()
        } else {
            onFinished?()
        }
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning { try engine.start() }
    }

    private func cancelFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        players.forEach { $0.volume = 1 }
    }

    private func finishFadeImmediately() {
        guard fadeTimer != nil else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        players[1 - activeIndex].stop()
        players.forEach { $0.volume = 1 }
    }

    /// Route or sample-rate changes stop the engine; restart and continue from the same spot.
    private func recoverFromConfigurationChange() {
        guard file != nil else { return }
        let wasPlaying = pausedAt == nil
        let position = currentTime
        try? startEngineIfNeeded()
        pausedAt = nil
        generation += 1
        players.forEach { $0.stop() }
        queuedFile = nil
        queuedURL = nil
        schedule(from: position)
        if wasPlaying { active.play() } else { pausedAt = position }
    }
}

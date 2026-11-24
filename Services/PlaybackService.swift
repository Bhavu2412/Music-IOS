import AVFoundation
import Combine
import MediaPlayer
import UIKit

@MainActor
protocol PlaybackServicing: AnyObject {
    var currentTrack: Track? { get }
    var queue: [Track] { get }
    var isPlaying: Bool { get }
    var elapsed: Double { get }
    var repeatMode: QueueRepeatMode { get }
    var isShuffled: Bool { get }

    func play(_ track: Track, from tracks: [Track])
    func playShuffled(_ tracks: [Track])
    func resume(from tracks: [Track])
    func togglePlayback()
    func next()
    func previous()
    func seek(to seconds: Double)
    func skip(by seconds: Double)
    func setRepeatMode(_ mode: QueueRepeatMode)
    func toggleShuffle()
    func setPlaybackRate(_ rate: Float)
    func addToQueue(_ track: Track)
    func playNext(_ track: Track)
    func moveQueue(from source: IndexSet, to destination: Int)
    func remove(trackIDs: Set<UUID>)
}

enum TrackTransitionDirection: Equatable {
    case next
    case previous
}

/// Elapsed time lives in its own object so the 2 Hz tick only re-renders
/// the views that show progress, not every view observing PlaybackService.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var elapsed: Double = 0
}

@MainActor
final class PlaybackService: ObservableObject, PlaybackServicing {
    static let shared = PlaybackService()

    @Published private(set) var currentTrack: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var repeatMode: QueueRepeatMode = .off
    @Published private(set) var isShuffled = false
    @Published private(set) var trackTransitionDirection: TrackTransitionDirection = .next
    @Published private(set) var playbackRate: Float
    @Published private(set) var eqPreset: EqualizerPreset
    @Published private(set) var crossfadeSeconds: Double
    @Published private(set) var isGaplessEnabled: Bool
    @Published var errorMessage: String?

    let clock = PlaybackClock()
    var elapsed: Double { clock.elapsed }

    private let engine = AudioEnginePlayer()
    private let defaults = UserDefaults.standard
    private let libraryService = LibraryService()
    private var state = QueueState()
    /// Queue order before shuffling, so turning shuffle off restores it.
    private var unshuffledIDs: [UUID] = []
    private var ticker: Timer?
    private var currentScopedURL: URL?
    /// Track queued gaplessly behind the current one in the engine.
    private var queuedTrack: Track?
    private var queuedScopedURL: URL?
    private var lastPersistedPosition: Double = 0

    private static let stateKey = "music.queueState"
    private static let rateKey = "music.playbackRate"
    private static let eqKey = "music.eqPreset"
    private static let crossfadeKey = "music.crossfadeSeconds"
    private static let gaplessKey = "music.gapless"
    /// How early the next track is lined up for gapless hand-off.
    private static let preloadLeadTime: Double = 10

    private init() {
        let defaults = UserDefaults.standard
        let savedRate = defaults.float(forKey: Self.rateKey)
        playbackRate = savedRate == 0 ? 1.0 : savedRate
        eqPreset = defaults.string(forKey: Self.eqKey).flatMap(EqualizerPreset.init(rawValue:)) ?? .flat
        crossfadeSeconds = defaults.double(forKey: Self.crossfadeKey)
        isGaplessEnabled = defaults.object(forKey: Self.gaplessKey) as? Bool ?? true
        engine.rate = playbackRate
        engine.setEQ(eqPreset)
        engine.onFinished = { [weak self] in self?.currentTrackFinished() }
        engine.onAdvancedToQueued = { [weak self] in self?.advanceToQueuedTrack() }
        configureAudioSession()
        installRemoteCommands()
        observeAudioSession()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard currentTrack != nil else { return }
        clock.elapsed = engine.currentTime
        // ponytail: persist every 5 s of playback, not every tick; worst case loses 5 s on a crash.
        if abs(clock.elapsed - lastPersistedPosition) >= 5 {
            persistState()
        }
        prepareUpcomingTransition()
    }

    /// Near the end of a track: start a crossfade, or line the next track up for a gapless hand-off.
    private func prepareUpcomingTransition() {
        guard isPlaying, let current = currentTrack, let upcoming = upcomingTrack() else { return }
        let remaining = (engine.duration - engine.currentTime) / Double(max(playbackRate, 0.5))
        guard remaining > 0 else { return }

        if crossfadeSeconds > 0, repeatMode != .one, upcoming.id != current.id, remaining <= crossfadeSeconds {
            crossfade(to: upcoming, over: remaining)
            return
        }
        let wantsGapless = isGaplessEnabled || repeatMode == .one
        guard wantsGapless, crossfadeSeconds == 0 || repeatMode == .one,
              queuedTrack == nil, remaining <= Self.preloadLeadTime,
              let url = try? libraryService.resolveURL(for: upcoming) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        if engine.queueNext(url) {
            queuedTrack = upcoming
            queuedScopedURL = scoped ? url : nil
        } else if scoped {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// The track that plays when the current one ends naturally.
    private func upcomingTrack() -> Track? {
        repeatMode == .one ? currentTrack : adjacentTrack(step: 1)
    }

    private func crossfade(to track: Track, over remaining: Double) {
        do {
            let url = try libraryService.resolveURL(for: track)
            let scoped = url.startAccessingSecurityScopedResource()
            try engine.crossfade(to: url, duration: min(crossfadeSeconds, remaining))
            // The outgoing file keeps playing for the fade, so release its access a little later.
            let outgoing = currentScopedURL
            DispatchQueue.main.asyncAfter(deadline: .now() + crossfadeSeconds + 1) {
                outgoing?.stopAccessingSecurityScopedResource()
            }
            currentScopedURL = scoped ? url : nil
            becomeCurrent(track)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func advanceToQueuedTrack() {
        guard let track = queuedTrack else { return }
        currentScopedURL?.stopAccessingSecurityScopedResource()
        currentScopedURL = queuedScopedURL
        queuedTrack = nil
        queuedScopedURL = nil
        becomeCurrent(track)
    }

    /// Bookkeeping when a track starts without a fresh load (gapless or crossfade).
    private func becomeCurrent(_ track: Track) {
        trackTransitionDirection = .next
        currentTrack = track
        track.playCount += 1
        track.lastPlayedAt = .now
        clock.elapsed = engine.currentTime
        persistState()
        publishState()
    }

    private func currentTrackFinished() {
        if repeatMode == .one {
            engine.seek(to: 0)
            engine.play()
        } else {
            next()
        }
    }

    /// Queue changed: drop a gaplessly queued track that is no longer the upcoming one.
    private func invalidateQueuedTrack() {
        guard let queued = queuedTrack, queued.id != upcomingTrack()?.id else { return }
        engine.clearQueued()
        queuedScopedURL?.stopAccessingSecurityScopedResource()
        queuedScopedURL = nil
        queuedTrack = nil
    }

    func setEQPreset(_ preset: EqualizerPreset) {
        eqPreset = preset
        engine.setEQ(preset)
        defaults.set(preset.rawValue, forKey: Self.eqKey)
    }

    func setCrossfade(_ seconds: Double) {
        crossfadeSeconds = min(max(seconds, 0), 12)
        defaults.set(crossfadeSeconds, forKey: Self.crossfadeKey)
        invalidateQueuedTrack()
    }

    func setGapless(_ enabled: Bool) {
        isGaplessEnabled = enabled
        defaults.set(enabled, forKey: Self.gaplessKey)
    }

    func play(_ track: Track, from tracks: [Track]) {
        trackTransitionDirection = .next
        queue = tracks
        if !queue.contains(where: { $0.id == track.id }) {
            queue.insert(track, at: 0)
        }
        unshuffledIDs = queue.map(\.id)
        if isShuffled {
            queue = [track] + queue.filter { $0.id != track.id }.shuffled()
        }
        start(track, at: 0)
    }

    func playShuffled(_ tracks: [Track]) {
        guard let first = tracks.randomElement() else { return }
        isShuffled = true
        play(first, from: tracks)
    }

    /// Restores the last session paused at its saved position. It never auto-plays on launch.
    func resume(from tracks: [Track]) {
        guard currentTrack == nil, let data = defaults.data(forKey: Self.stateKey) else { return }
        let saved: QueueState
        do {
            saved = try JSONDecoder().decode(QueueState.self, from: data)
        } catch {
            errorMessage = "Saved playback state could not be restored."
            return
        }
        state = saved
        let lookup = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        queue = saved.trackIDs.compactMap { lookup[$0] }
        unshuffledIDs = queue.map(\.id)
        repeatMode = saved.repeatMode
        isShuffled = saved.isShuffled
        guard let id = saved.currentTrackID, let track = lookup[id] else { return }
        start(track, at: saved.position, autoplay: false)
    }

    func togglePlayback() {
        isPlaying ? pausePlayback() : startPlayback()
    }

    func next() {
        trackTransitionDirection = .next
        guard let track = adjacentTrack(step: 1) else {
            // End of queue with repeat off: stop at the start of the last track.
            engine.pause()
            isPlaying = false
            seek(to: 0)
            publishState()
            return
        }
        start(track, at: 0)
    }

    func previous() {
        trackTransitionDirection = .previous
        if elapsed > 3 {
            seek(to: 0)
            return
        }
        guard let track = adjacentTrack(step: -1) else {
            seek(to: 0)
            return
        }
        start(track, at: 0)
    }

    func seek(to seconds: Double) {
        guard currentTrack != nil else { return }
        releaseQueuedTrack()
        engine.seek(to: seconds)
        clock.elapsed = engine.currentTime
        persistState()
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: elapsed + seconds)
    }

    func setRepeatMode(_ mode: QueueRepeatMode) {
        repeatMode = mode
        invalidateQueuedTrack()
        persistState()
    }

    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            unshuffledIDs = queue.map(\.id)
            let current = queue.filter { $0.id == currentTrack?.id }
            queue = current + queue.filter { $0.id != currentTrack?.id }.shuffled()
        } else {
            let order = Dictionary(unshuffledIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            // Tracks queued after shuffling (not in the original order) stay at the end.
            queue = queue.enumerated()
                .sorted { (order[$0.element.id] ?? Int.max, $0.offset) < (order[$1.element.id] ?? Int.max, $1.offset) }
                .map(\.element)
        }
        invalidateQueuedTrack()
        persistState()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.0, rate))
        engine.rate = playbackRate
        defaults.set(playbackRate, forKey: Self.rateKey)
        updateNowPlaying()
    }

    func addToQueue(_ track: Track) {
        queue.append(track)
        unshuffledIDs.append(track.id)
        invalidateQueuedTrack()
        persistState()
    }

    func playNext(_ track: Track) {
        guard track.id != currentTrack?.id else { return }
        queue.removeAll { $0.id == track.id }
        let insertionIndex = queue.firstIndex(where: { $0.id == currentTrack?.id })
            .map { $0 + 1 } ?? 0
        queue.insert(track, at: insertionIndex)
        invalidateQueuedTrack()
        persistState()
    }

    func moveQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        invalidateQueuedTrack()
        persistState()
    }

    /// Call before deleting tracks from SwiftData so nothing keeps a reference to a deleted model.
    func remove(trackIDs: Set<UUID>) {
        guard !trackIDs.isEmpty else { return }
        queue.removeAll { trackIDs.contains($0.id) }
        unshuffledIDs.removeAll { trackIDs.contains($0) }
        if let current = currentTrack, trackIDs.contains(current.id) {
            stop()
        } else {
            invalidateQueuedTrack()
        }
        persistState()
    }

    private func releaseQueuedTrack() {
        queuedScopedURL?.stopAccessingSecurityScopedResource()
        queuedScopedURL = nil
        queuedTrack = nil
    }

    private func stop() {
        engine.stop()
        releaseQueuedTrack()
        currentScopedURL?.stopAccessingSecurityScopedResource()
        currentScopedURL = nil
        currentTrack = nil
        isPlaying = false
        clock.elapsed = 0
        updateNowPlaying()
    }

    private func start(_ track: Track, at position: Double, autoplay: Bool = true) {
        do {
            let url = try libraryService.resolveURL(for: track)
            releaseQueuedTrack()
            currentScopedURL?.stopAccessingSecurityScopedResource()
            currentScopedURL = url.startAccessingSecurityScopedResource() ? url : nil
            if autoplay { try? AVAudioSession.sharedInstance().setActive(true) }
            try engine.load(url, at: position, autoplay: autoplay)
            currentTrack = track
            if autoplay {
                track.playCount += 1
                track.lastPlayedAt = .now
            }
            clock.elapsed = engine.currentTime
            isPlaying = autoplay
            persistState()
            publishState()
        } catch {
            isPlaying = false
            currentTrack = nil
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "“\(track.title)” couldn’t be played. The file may be damaged or in an unsupported format."
        }
    }

    private func adjacentTrack(step: Int) -> Track? {
        guard let currentTrack,
              let index = queue.firstIndex(where: { $0.id == currentTrack.id }) else { return nil }
        let nextIndex = index + step
        if queue.indices.contains(nextIndex) { return queue[nextIndex] }
        return repeatMode == .all ? (step > 0 ? queue.first : queue.last) : nil
    }

    private func persistState() {
        state.trackIDs = queue.map(\.id)
        state.currentTrackID = currentTrack?.id
        state.position = elapsed
        state.repeatMode = repeatMode
        state.isShuffled = isShuffled
        lastPersistedPosition = elapsed
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: Self.stateKey)
        } catch {
            errorMessage = "Playback progress could not be saved."
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observeAudioSession() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .began:
                    self.pausePlayback()
                case .ended where shouldResume:
                    self.startPlayback()
                default:
                    break
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.pausePlayback() }
        }
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.startPlayback() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pausePlayback() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        // With skip commands on, iOS swaps next/previous for ±15 s buttons in the Dynamic Island and lock screen.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    /// Lock screen info. The system extrapolates elapsed time from the rate, so this only runs on state changes.
    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(playbackRate)
        ]
        if track.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = track.duration }
        if let data = track.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Lock screen, Dynamic Island (system Now Playing), widgets, and controls. Called on track or play-state changes only (widget reloads are budgeted).
    private func publishState() {
        updateNowPlaying()
        guard let track = currentTrack else { return }
        WidgetDataService.shared.saveNowPlayingState(WidgetTrackState(
            title: track.title,
            artist: track.artist,
            artworkData: WidgetDataService.downscaledJPEG(track.artworkData, side: 600, quality: 0.8),
            isPlaying: isPlaying,
            queueCount: queue.count
        ))
    }

    func startPlayback() {
        guard currentTrack != nil, !isPlaying else { return }
        // A widget or control may launch the app in the background, or an interruption may have deactivated the session.
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.play()
        isPlaying = true
        persistState()
        publishState()
    }

    func pausePlayback() {
        guard isPlaying else { return }
        engine.pause()
        clock.elapsed = engine.currentTime
        isPlaying = false
        persistState()
        publishState()
    }
}

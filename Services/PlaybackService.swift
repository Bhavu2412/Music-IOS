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
    func resume(from tracks: [Track])
    func togglePlayback()
    func next()
    func previous()
    func seek(to seconds: Double)
    func skip(by seconds: Double)
    func setRepeatMode(_ mode: QueueRepeatMode)
    func toggleShuffle()
    func setPlaybackRate(_ rate: Float)
    func setCrossfade(_ seconds: Double)
    func addToQueue(_ track: Track)
    func playNext(_ track: Track)
    func moveQueue(from source: IndexSet, to destination: Int)
}

enum TrackTransitionDirection: Equatable {
    case next
    case previous
}

@MainActor
final class PlaybackService: ObservableObject, PlaybackServicing {
    static let shared = PlaybackService()

    @Published private(set) var currentTrack: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var repeatMode: QueueRepeatMode = .off
    @Published private(set) var isShuffled = false
    @Published private(set) var trackTransitionDirection: TrackTransitionDirection = .next
    @Published private(set) var playbackRate: Float = 1.0
    @Published var errorMessage: String?

    private let player = AVPlayer()
    private let defaults = UserDefaults.standard
    private let libraryService = LibraryService()
    private var state = QueueState()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var currentScopedURL: URL?

    private init() {
        configureAudioSession()
        installRemoteCommands()
        observeAudioSession()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = max(time.seconds.isFinite ? time.seconds : 0, 0)
                self.state.position = self.elapsed
                self.persistState()
                self.updateNowPlaying()
            }
        }
    }

    func play(_ track: Track, from tracks: [Track]) {
        trackTransitionDirection = .next
        queue = tracks
        if !queue.contains(where: { $0.id == track.id }) {
            queue.insert(track, at: 0)
        }
        state.trackIDs = queue.map(\.id)
        state.currentTrackID = track.id
        start(track, at: 0)
    }

    func resume(from tracks: [Track]) {
        guard let data = defaults.data(forKey: "music.queueState") else { return }
        let saved: QueueState
        do {
            saved = try JSONDecoder().decode(QueueState.self, from: data)
        } catch {
            errorMessage = "Saved playback state could not be restored."
            return
        }
        state = saved
        let lookup = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        queue = saved.trackIDs.compactMap { lookup[$0] }
        repeatMode = saved.repeatMode
        isShuffled = saved.isShuffled
        guard let id = saved.currentTrackID, let track = lookup[id] else { return }
        start(track, at: saved.position)
    }

    func togglePlayback() {
        guard currentTrack != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
        persistState()
    }

    func next() {
        trackTransitionDirection = .next
        guard let track = adjacentTrack(step: 1) else {
            if repeatMode == .all, let first = queue.first { start(first, at: 0) }
            else { isPlaying = false }
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
        guard let item = player.currentItem else { return }
        let end = item.duration.seconds.isFinite ? item.duration.seconds : seconds
        let target = min(max(seconds, 0), max(end, 0))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        state.position = target
        persistState()
    }

    func skip(by seconds: Double) {
        seek(to: elapsed + seconds)
    }

    func setRepeatMode(_ mode: QueueRepeatMode) {
        repeatMode = mode
        state.repeatMode = mode
        persistState()
    }

    func toggleShuffle() {
        isShuffled.toggle()
        state.isShuffled = isShuffled
        if isShuffled, let currentTrack {
            queue = queue.filter { $0.id == currentTrack.id } +
                queue.filter { $0.id != currentTrack.id }.shuffled()
        }
        state.trackIDs = queue.map(\.id)
        persistState()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.0, rate))
        player.rate = playbackRate
    }

    func setCrossfade(_ seconds: Double) {
        _ = seconds
    }

    func addToQueue(_ track: Track) {
        queue.append(track)
        state.trackIDs = queue.map(\.id)
        persistState()
    }

    func playNext(_ track: Track) {
        let insertionIndex = queue.firstIndex(where: { $0.id == currentTrack?.id })
            .map { $0 + 1 } ?? 0
        queue.insert(track, at: insertionIndex)
        state.trackIDs = queue.map(\.id)
        persistState()
    }

    func moveQueue(from source: IndexSet, to destination: Int) {
        let orderedIndices = source.sorted()
        let moving = orderedIndices.map { queue[$0] }
        for index in orderedIndices.reversed() {
            queue.remove(at: index)
        }
        let adjustedDestination = destination - orderedIndices.filter { $0 < destination }.count
        queue.insert(contentsOf: moving, at: min(max(adjustedDestination, 0), queue.count))
        state.trackIDs = queue.map(\.id)
        persistState()
    }

    private func start(_ track: Track, at position: Double) {
        do {
            let url = try libraryService.resolveURL(for: track)
            if let currentScopedURL { currentScopedURL.stopAccessingSecurityScopedResource() }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            currentScopedURL = didStartAccessing ? url : nil
            currentTrack = track
            track.playCount += 1
            state.currentTrackID = track.id
            state.position = position
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.seek(to: CMTime(seconds: max(position, 0), preferredTimescale: 600))
            player.play()
            isPlaying = true
            elapsed = position
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.repeatMode == .one { self.seek(to: 0); self.player.play() }
                    else { self.next() }
                }
            }
            persistState()
            updateNowPlaying()
        } catch {
            isPlaying = false
            currentTrack = nil
            errorMessage = error.localizedDescription
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
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: "music.queueState")
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
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                if type == .began {
                    self?.player.pause()
                    self?.isPlaying = false
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
            Task { @MainActor in
                self?.player.pause()
                self?.isPlaying = false
            }
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
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 15) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if track.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = track.duration }
        if let data = track.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        let widgetState = WidgetTrackState(
            title: track.title,
            artist: track.artist,
            artworkData: track.artworkData,
            isPlaying: isPlaying,
            queueCount: queue.count
        )
        WidgetDataService.shared.saveNowPlayingState(widgetState)

        if #available(iOS 16.1, *) {
            LiveActivityService.shared.startActivity(track: track)
        }
    }

    func startPlayback() {
        guard currentTrack != nil else { return }
        player.play()
        isPlaying = true
        updateNowPlaying()
        persistState()
    }

    func pausePlayback() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
        persistState()
    }
}

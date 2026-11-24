import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<NowPlayingAttributes>?

    /// One activity per track: ends the previous one and requests a new one.
    func startActivity(track: Track, isPlaying: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        stopActivity()
        let state = NowPlayingAttributes.ContentState(track: track.title, artist: track.artist, artworkData: track.artworkData, isPlaying: isPlaying)
        do {
            activity = try Activity.request(
                attributes: NowPlayingAttributes(name: track.title),
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            print("Live Activity unavailable: \(error.localizedDescription)")
        }
    }

    func update(track: Track, isPlaying: Bool) {
        guard let activity else { return }
        let state = NowPlayingAttributes.ContentState(track: track.title, artist: track.artist, artworkData: track.artworkData, isPlaying: isPlaying)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func stopActivity() {
        let currentActivity = activity
        activity = nil
        Task { await currentActivity?.end(nil, dismissalPolicy: .immediate) }
    }
}

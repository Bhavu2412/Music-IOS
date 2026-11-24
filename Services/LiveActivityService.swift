import ActivityKit
import Foundation

@available(iOS 16.1, *)
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<NowPlayingAttributes>?

    func startActivity(track: Track) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = NowPlayingAttributes(name: track.title)
        let state = NowPlayingAttributes.ContentState(track: track.title, artist: track.artist, isPlaying: true)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            activity = try Activity.request(attributes: attributes, content: content)
        } catch {
            print("Live Activity unavailable: \(error.localizedDescription)")
        }
    }

    func stopActivity() {
        let currentActivity = activity
        activity = nil
        Task {
            await currentActivity?.end(nil, dismissalPolicy: .immediate)
        }
    }
}

struct NowPlayingAttributes: ActivityAttributes {
    public typealias ContentState = DynamicIslandState

    var name: String
}

struct DynamicIslandState: Codable & Hashable {
    var track: String
    var artist: String
    var isPlaying: Bool
}

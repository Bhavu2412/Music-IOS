import Foundation
import WidgetKit

struct WidgetTrackState: Codable {
    let title: String
    let artist: String
    let artworkData: Data?
    let isPlaying: Bool
    let queueCount: Int
}

protocol WidgetDataServicing {
    func saveNowPlayingState(_ state: WidgetTrackState)
    func loadNowPlayingState() -> WidgetTrackState?
}

final class WidgetDataService: WidgetDataServicing {
    static let shared = WidgetDataService()

    /// Set per build from APP_GROUP_ID (see project.yml), so it always matches the entitlement.
    private let suiteName = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
        ?? "group.com.yourcompany.Music"
    private let key = "music.nowPlaying.widget"

    func saveNowPlayingState(_ state: WidgetTrackState) {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(state) {
            userDefaults.set(data, forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func loadNowPlayingState() -> WidgetTrackState? {
        guard let userDefaults = UserDefaults(suiteName: suiteName),
              let data = userDefaults.data(forKey: key),
              let state = try? JSONDecoder().decode(WidgetTrackState.self, from: data) else { return nil }
        return state
    }
}

// Shared with the widget extension so it can render the Live Activity.
#if canImport(ActivityKit)
import ActivityKit

struct NowPlayingAttributes: ActivityAttributes {
    public typealias ContentState = DynamicIslandState

    var name: String
}

struct DynamicIslandState: Codable & Hashable {
    var track: String
    var artist: String
    var isPlaying: Bool
}
#endif

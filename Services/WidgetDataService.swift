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

    private let suiteName = "group.com.yourcompany.Music"
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

import Foundation
import UIKit
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
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }

    /// Square, aspect-filled JPEG. Widgets run in ~30 MB and drop oversized images,
    /// so they never get the original artwork.
    static func downscaledJPEG(_ data: Data?, side: CGFloat, quality: CGFloat) -> Data? {
        guard let data, let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = max(side / image.size.width, side / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .jpegData(withCompressionQuality: quality) { _ in
                image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
            }
    }

    func loadNowPlayingState() -> WidgetTrackState? {
        guard let userDefaults = UserDefaults(suiteName: suiteName),
              let data = userDefaults.data(forKey: key),
              let state = try? JSONDecoder().decode(WidgetTrackState.self, from: data) else { return nil }
        return state
    }
}

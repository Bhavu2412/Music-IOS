import ActivityKit
import Foundation
import UIKit

@available(iOS 16.1, *)
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()

    private var activity: Activity<NowPlayingAttributes>?

    /// One activity per track: ends the previous one and requests a new one.
    func startActivity(track: Track, isPlaying: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        stopActivity()
        let state = NowPlayingAttributes.ContentState(track: track.title, artist: track.artist, artworkData: Self.thumbnail(track.artworkData), isPlaying: isPlaying)
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
        let state = NowPlayingAttributes.ContentState(track: track.title, artist: track.artist, artworkData: Self.thumbnail(track.artworkData), isPlaying: isPlaying)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// ActivityKit rejects payloads over 4 KB (and the artwork is base64-encoded inside it),
    /// so the Live Activity gets a tiny thumbnail, or none if it still doesn't fit.
    static func thumbnail(_ data: Data?) -> Data? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: 44, height: 44)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.5) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return jpeg.count <= 1_800 ? jpeg : nil
    }

    func stopActivity() {
        let currentActivity = activity
        activity = nil
        Task { await currentActivity?.end(nil, dismissalPolicy: .immediate) }
    }
}

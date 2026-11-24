import SwiftData
import SwiftUI

@main
struct MusicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LibraryTabsView()
        }
        .modelContainer(MusicStore.container)
    }
}

/// One library store shared by the UI, App Intents (Siri, widgets, Control Center) and CarPlay.
@MainActor
enum MusicStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Track.self, Playlist.self, Album.self)
        } catch {
            fatalError("Could not open the music library: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }

    static func allTracks() -> [Track] {
        (try? context.fetch(FetchDescriptor<Track>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]))) ?? []
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { DownloadService.shared.reconnect() }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        MainActor.assumeIsolated {
            DownloadService.shared.backgroundCompletionHandler = completionHandler
            DownloadService.shared.reconnect()
        }
    }
}

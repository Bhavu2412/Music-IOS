import SwiftData
import SwiftUI

@main
struct MusicApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryTabsView()
        }
        .modelContainer(for: [Track.self, Playlist.self, Album.self])
    }
}

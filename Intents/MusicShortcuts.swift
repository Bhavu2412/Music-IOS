import AppIntents
import SwiftData

/// Runs a playback action, first restoring the last session if the app was just launched by the intent.
@MainActor
enum PlaybackIntentRunner {
    static func run(_ action: @MainActor (PlaybackService) -> Void) {
        let playback = PlaybackService.shared
        if playback.currentTrack == nil {
            playback.resume(from: MusicStore.allTracks())
        }
        action(playback)
    }
}

// MARK: - Playlists for Siri

struct PlaylistEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    static var defaultQuery = PlaylistQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ playlist: Playlist) {
        id = playlist.id
        name = playlist.name
    }
}

struct PlaylistQuery: EntityStringQuery {
    @MainActor
    private func all() -> [PlaylistEntity] {
        let playlists = (try? MusicStore.context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return playlists.map(PlaylistEntity.init)
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PlaylistEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PlaylistEntity] {
        all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PlaylistEntity] {
        all()
    }
}

struct PlayPlaylistIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play Playlist"
    static var description = IntentDescription("Plays one of your playlists.")

    @Parameter(title: "Playlist")
    var playlist: PlaylistEntity

    @Parameter(title: "Shuffle", default: false)
    var shuffle: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$playlist)") { \.$shuffle }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = playlist.id
        guard let stored = try MusicStore.context.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == id })).first else {
            return .result(dialog: "I couldn’t find that playlist.")
        }
        let lookup = Dictionary(MusicStore.allTracks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tracks = stored.trackIDs.compactMap { lookup[$0] }
        guard let first = tracks.first else {
            return .result(dialog: "\(stored.name) is empty.")
        }
        if shuffle {
            PlaybackService.shared.playShuffled(tracks)
        } else {
            PlaybackService.shared.play(first, from: tracks)
        }
        return .result(dialog: "Playing \(stored.name).")
    }
}

struct ShuffleLibraryIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Shuffle Library"
    static var description = IntentDescription("Shuffles every song in your library.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tracks = MusicStore.allTracks()
        guard !tracks.isEmpty else { return .result(dialog: "Your library is empty.") }
        PlaybackService.shared.playShuffled(tracks)
        return .result(dialog: "Shuffling \(tracks.count) songs.")
    }
}

struct PlayFavoritesIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play Favorites"
    static var description = IntentDescription("Shuffles your favorite songs.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let favorites = MusicStore.allTracks().filter(\.isFavorite)
        guard !favorites.isEmpty else { return .result(dialog: "You don’t have any favorites yet.") }
        PlaybackService.shared.playShuffled(favorites)
        return .result(dialog: "Playing your favorites.")
    }
}

// MARK: - Siri phrases

struct MusicShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: [
                "Play \(\.$playlist) in \(.applicationName)",
                "Play my \(\.$playlist) playlist in \(.applicationName)",
            ],
            shortTitle: "Play Playlist",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: ShuffleLibraryIntent(),
            phrases: ["Shuffle my music in \(.applicationName)", "Shuffle \(.applicationName)"],
            shortTitle: "Shuffle Library",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: PlayFavoritesIntent(),
            phrases: ["Play my favorites in \(.applicationName)"],
            shortTitle: "Play Favorites",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: PlayPauseIntent(),
            phrases: ["Pause \(.applicationName)", "Resume \(.applicationName)"],
            shortTitle: "Play or Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: NextTrackIntent(),
            phrases: ["Next song in \(.applicationName)", "Skip this song in \(.applicationName)"],
            shortTitle: "Next Song",
            systemImageName: "forward.fill"
        )
    }
}

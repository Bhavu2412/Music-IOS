import Foundation
import SwiftData

/// Syncs favorites and playlists across devices through iCloud key-value storage.
///
/// Audio files stay on each device, so track IDs differ between devices; songs are matched
/// by a "title|artist" key. Each favorite and each playlist is its own last-writer-wins register,
/// and deleted playlists leave a tombstone so they don't come back.
/// Local edits are detected by diffing against the state from the previous sync.
// ponytail: whole-state sync on launch/background/remote-change; fine for KV store's 1 MB cap. Move to CloudKit if libraries outgrow it.
@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()
    static let enabledKey = "music.iCloudSync"

    private let store = NSUbiquitousKeyValueStore.default
    private let remoteKey = "music.library.v1"
    private let lastSyncedKey = "music.cloud.lastSynced"

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { _ in
            MainActor.assumeIsolated { CloudSyncService.shared.sync() }
        }
    }

    func start() {
        store.synchronize()
        sync()
    }

    func sync(now: Date = .now) {
        guard isEnabled else { return }
        let context = MusicStore.context
        let tracks = (try? context.fetch(FetchDescriptor<Track>())) ?? []
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        let last = decode(UserDefaults.standard.data(forKey: lastSyncedKey)) ?? CloudState()
        let remote = decode(store.data(forKey: remoteKey)) ?? CloudState()

        let local = CloudState.local(tracks: tracks, playlists: playlists, since: last, now: now)
        let merged = local.merged(with: remote)
        merged.apply(to: tracks, playlists: playlists, in: context)
        try? context.save()

        guard let data = try? JSONEncoder().encode(merged) else { return }
        if store.data(forKey: remoteKey) != data { store.set(data, forKey: remoteKey) }
        UserDefaults.standard.set(data, forKey: lastSyncedKey)
    }

    private func decode(_ data: Data?) -> CloudState? {
        data.flatMap { try? JSONDecoder().decode(CloudState.self, from: $0) }
    }
}

struct Stamped<Value: Codable & Equatable>: Codable, Equatable {
    var value: Value
    var at: Date
}

struct CloudPlaylist: Codable, Equatable {
    var name: String
    var createdAt: Date
    var trackKeys: [String]
}

struct CloudState: Codable, Equatable {
    var favorites: [String: Stamped<Bool>] = [:]
    /// nil value = deleted (tombstone).
    var playlists: [UUID: Stamped<CloudPlaylist?>] = [:]

    static func key(for track: Track) -> String {
        func norm(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(norm(track.title))|\(norm(track.artist))"
    }

    /// This device's state, stamping anything that changed since the last sync with `now`.
    static func local(tracks: [Track], playlists: [Playlist], since last: CloudState, now: Date) -> CloudState {
        var state = last
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localKeys = Set(tracks.map(key(for:)))

        var favoriteByKey: [String: Bool] = [:]
        for track in tracks where track.isFavorite { favoriteByKey[key(for: track)] = true }
        for track in tracks where favoriteByKey[key(for: track)] == nil { favoriteByKey[key(for: track)] = false }
        for (key, isFavorite) in favoriteByKey where (state.favorites[key]?.value ?? false) != isFavorite {
            state.favorites[key] = Stamped(value: isFavorite, at: now)
        }

        var seen = Set<UUID>()
        for playlist in playlists {
            seen.insert(playlist.id)
            let resolved = playlist.trackIDs.compactMap { byID[$0].map(key(for:)) }
            // Keep songs this device doesn't have, so syncing here never drops them for others.
            let previous = last.playlists[playlist.id]?.value ?? nil
            let unknown = (previous?.trackKeys ?? []).filter { !localKeys.contains($0) }
            let current = CloudPlaylist(name: playlist.name, createdAt: playlist.createdAt, trackKeys: resolved + unknown)
            if (state.playlists[playlist.id]?.value ?? nil) != current {
                state.playlists[playlist.id] = Stamped(value: current, at: now)
            }
        }
        for (id, entry) in last.playlists where entry.value != nil && !seen.contains(id) {
            state.playlists[id] = Stamped(value: nil, at: now) // deleted on this device
        }
        return state
    }

    /// Per-entry last-writer-wins.
    func merged(with other: CloudState) -> CloudState {
        CloudState(
            favorites: favorites.merging(other.favorites) { $1.at > $0.at ? $1 : $0 },
            playlists: playlists.merging(other.playlists) { $1.at > $0.at ? $1 : $0 }
        )
    }

    @MainActor
    func apply(to tracks: [Track], playlists: [Playlist], in context: ModelContext) {
        var tracksByKey: [String: [Track]] = [:]
        for track in tracks { tracksByKey[Self.key(for: track), default: []].append(track) }

        for (key, stamped) in favorites {
            for track in tracksByKey[key] ?? [] where track.isFavorite != stamped.value {
                track.isFavorite = stamped.value
            }
        }

        let existing = Dictionary(playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, stamped) in self.playlists {
            guard let remote = stamped.value else {
                if let playlist = existing[id] { context.delete(playlist) }
                continue
            }
            let ids = remote.trackKeys.compactMap { tracksByKey[$0]?.first?.id }
            if let playlist = existing[id] {
                if playlist.name != remote.name { playlist.name = remote.name }
                if playlist.trackIDs != ids { playlist.trackIDs = ids }
            } else {
                context.insert(Playlist(id: id, name: remote.name, trackIDs: ids, createdAt: remote.createdAt))
            }
        }
    }
}

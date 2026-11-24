import CarPlay
import SwiftData
import UIKit

/// CarPlay audio UI: Songs, Playlists and Smart Playlists tabs, plus the system Now Playing
/// screen (driven by MPNowPlayingInfoCenter and the remote commands PlaybackService installs).
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        MainActor.assumeIsolated {
            self.interfaceController = interfaceController
            configureNowPlaying()
            let tabs = CPTabBarTemplate(templates: [songsTab(), playlistsTab(), smartTab()])
            interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: - Tabs

    @MainActor
    private func songsTab() -> CPListTemplate {
        let tracks = SongSort.title.sorted(MusicStore.allTracks())
        let shuffle = CPListItem(text: "Shuffle All", detailText: "\(tracks.count) songs", image: UIImage(systemName: "shuffle"))
        shuffle.handler = { [weak self] _, completion in
            MainActor.assumeIsolated {
                PlaybackService.shared.playShuffled(tracks)
                self?.showNowPlaying()
            }
            completion()
        }
        let template = CPListTemplate(
            title: "Songs",
            sections: [CPListSection(items: [shuffle]), CPListSection(items: items(for: tracks))]
        )
        template.tabImage = UIImage(systemName: "music.note")
        template.emptyViewTitleVariants = ["No Songs"]
        template.emptyViewSubtitleVariants = ["Import music on your iPhone."]
        return template
    }

    @MainActor
    private func playlistsTab() -> CPListTemplate {
        let playlists = (try? MusicStore.context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let lookup = Dictionary(MusicStore.allTracks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows: [CPListItem] = playlists.map { playlist in
            let tracks = playlist.trackIDs.compactMap { lookup[$0] }
            let item = CPListItem(text: playlist.name, detailText: "\(tracks.count) songs",
                                  image: thumbnail(tracks.first?.artworkData) ?? UIImage(systemName: "music.note.list"))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated { self?.push(title: playlist.name, tracks: tracks) }
                completion()
            }
            return item
        }
        let template = CPListTemplate(title: "Playlists", sections: [CPListSection(items: rows)])
        template.tabImage = UIImage(systemName: "music.note.list")
        template.emptyViewTitleVariants = ["No Playlists"]
        return template
    }

    @MainActor
    private func smartTab() -> CPListTemplate {
        let library = MusicStore.allTracks()
        let favorites = library.filter(\.isFavorite)
        var rows: [CPListItem] = []
        let favoritesItem = CPListItem(text: "Favorites", detailText: "\(favorites.count) songs", image: UIImage(systemName: "heart.fill"))
        favoritesItem.accessoryType = .disclosureIndicator
        favoritesItem.handler = { [weak self] _, completion in
            MainActor.assumeIsolated { self?.push(title: "Favorites", tracks: favorites) }
            completion()
        }
        rows.append(favoritesItem)
        for smart in SmartPlaylist.allCases {
            let tracks = smart.tracks(from: library)
            let item = CPListItem(text: smart.rawValue, detailText: "\(tracks.count) songs", image: UIImage(systemName: smart.symbol))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated { self?.push(title: smart.rawValue, tracks: tracks) }
                completion()
            }
            rows.append(item)
        }
        let template = CPListTemplate(title: "For You", sections: [CPListSection(items: rows)])
        template.tabImage = UIImage(systemName: "sparkles")
        return template
    }

    // MARK: - Helpers

    @MainActor
    private func items(for tracks: [Track]) -> [CPListItem] {
        // ponytail: first `maximumItemCount` songs only; add paging/sections if libraries exceed it.
        tracks.prefix(CPListTemplate.maximumItemCount).map { track in
            let item = CPListItem(text: track.title, detailText: track.artist, image: thumbnail(track.artworkData))
            item.isPlaying = PlaybackService.shared.currentTrack?.id == track.id
            item.handler = { [weak self] _, completion in
                MainActor.assumeIsolated {
                    PlaybackService.shared.play(track, from: tracks)
                    self?.showNowPlaying()
                }
                completion()
            }
            return item
        }
    }

    @MainActor
    private func push(title: String, tracks: [Track]) {
        let template = CPListTemplate(title: title, sections: [CPListSection(items: items(for: tracks))])
        template.emptyViewTitleVariants = ["No Songs"]
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    @MainActor
    private func showNowPlaying() {
        guard let interfaceController,
              interfaceController.topTemplate !== CPNowPlayingTemplate.shared else { return }
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    @MainActor
    private func configureNowPlaying() {
        let shuffle = CPNowPlayingShuffleButton { _ in
            MainActor.assumeIsolated { PlaybackService.shared.toggleShuffle() }
        }
        let repeatButton = CPNowPlayingRepeatButton { _ in
            MainActor.assumeIsolated {
                let playback = PlaybackService.shared
                let next: QueueRepeatMode = switch playback.repeatMode {
                case .off: .all
                case .all: .one
                case .one: .off
                }
                playback.setRepeatMode(next)
            }
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([shuffle, repeatButton])
    }

    private func thumbnail(_ data: Data?) -> UIImage? {
        guard let data, let image = UIImage(data: data) else { return nil }
        let size = CPListItem.maximumImageSize
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

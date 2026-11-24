import SwiftUI

/// Detail page for any list of songs: an album, an artist, or a smart playlist.
struct TrackCollectionView: View {
    let title: String
    var subtitle: String? = nil
    var artworkData: Data? = nil
    var showsArtistAvatar = false
    var emptyMessage = "No songs here yet."
    let tracks: [Track]
    @ObservedObject var playback: PlaybackService
    let onTrackSelected: () -> Void

    private var totalDuration: String {
        let minutes = Int(tracks.reduce(0) { $0 + $1.duration } / 60)
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    if showsArtistAvatar {
                        DesignSystem.ArtistAvatar(name: title, size: 160)
                    } else {
                        DesignSystem.ArtworkView(data: artworkData ?? tracks.first?.artworkData, size: 200, placeholderKey: title, cornerRadius: 24)
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    }
                    VStack(spacing: 4) {
                        Text(title)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(DesignSystem.AppColors.accent)
                        }
                        Text("\(tracks.count) \(tracks.count == 1 ? "song" : "songs") · \(totalDuration)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        DesignSystem.GlassButton(title: "Play", icon: .play, action: play, style: .primary)
                        DesignSystem.GlassButton(title: "Shuffle", icon: .shuffle, action: shuffle, style: .secondary)
                    }
                    .disabled(tracks.isEmpty)
                    .opacity(tracks.isEmpty ? 0.5 : 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                if tracks.isEmpty {
                    Text(emptyMessage)
                        .font(DesignSystem.subhead)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                ForEach(tracks) { track in
                    DesignSystem.TrackRow(
                        track: track,
                        isCurrent: playback.currentTrack?.id == track.id,
                        isPlaying: playback.isPlaying
                    ) {
                        playback.play(track, from: tracks)
                        onTrackSelected()
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { playback.playNext(track) } label: {
                            Label("Play Next", systemImage: AppIcon.playNext.symbolName())
                        }
                        .tint(DesignSystem.AppColors.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { playback.addToQueue(track) } label: {
                            Label("Add to Queue", systemImage: AppIcon.addQueue.symbolName())
                        }
                        .tint(DesignSystem.AppColors.accent)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DesignSystem.AppColors.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 16)
    }

    private func play() {
        guard let first = tracks.first else { return }
        playback.play(first, from: tracks)
        onTrackSelected()
        Haptics.impact(.medium)
    }

    private func shuffle() {
        playback.playShuffled(tracks)
        onTrackSelected()
        Haptics.impact(.medium)
    }
}

/// Auto-updating playlists built from library data.
enum SmartPlaylist: String, CaseIterable, Identifiable {
    case recentlyAdded = "Recently Added"
    case recentlyPlayed = "Recently Played"
    case mostPlayed = "Most Played"
    case neverPlayed = "Never Played"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .recentlyAdded: "clock.badge.plus"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .mostPlayed: "flame"
        case .neverPlayed: "sparkles"
        }
    }

    var emptyMessage: String {
        switch self {
        case .recentlyAdded: "Import music to see it here."
        case .recentlyPlayed, .mostPlayed: "Play some songs and they’ll show up here."
        case .neverPlayed: "You’ve played everything. Nice."
        }
    }

    func tracks(from library: [Track]) -> [Track] {
        let limit = 50
        switch self {
        case .recentlyAdded:
            return Array(library.sorted { $0.dateAdded > $1.dateAdded }.prefix(limit))
        case .recentlyPlayed:
            return Array(library.filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
                .prefix(limit))
        case .mostPlayed:
            return Array(library.filter { $0.playCount > 0 }
                .sorted { ($0.playCount, $0.title) > ($1.playCount, $1.title) }
                .prefix(limit))
        case .neverPlayed:
            return library.filter { $0.playCount == 0 }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}

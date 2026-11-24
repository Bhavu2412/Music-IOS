import SwiftUI

/// Lyrics panel for Now Playing. Synced lyrics follow playback; tap a line to jump to it.
struct LyricsView: View {
    let track: Track
    @ObservedObject var playback: PlaybackService
    @ObservedObject var clock: PlaybackClock
    var onAddLyrics: (() -> Void)? = nil
    @State private var lyrics: Lyrics?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(DesignSystem.AppColors.accent)
            } else if case .synced(let lines) = lyrics {
                synced(lines)
            } else if case .plain(let text) = lyrics {
                ScrollView {
                    Text(text)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(DesignSystem.AppColors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(DesignSystem.AppColors.accent)
                    Text("No lyrics for this song")
                        .font(DesignSystem.headline)
                    Text("Paste lyrics in Edit Info, or put a matching .lrc file next to the song.")
                        .font(DesignSystem.subhead)
                        .foregroundStyle(DesignSystem.AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                    if let onAddLyrics {
                        Button("Add Lyrics", action: onAddLyrics)
                            .font(DesignSystem.body.weight(.semibold))
                            .foregroundStyle(DesignSystem.AppColors.accent)
                            .frame(minHeight: 44)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(track.id)-\(track.lyrics?.hashValue ?? 0)") {
            isLoading = true
            lyrics = await LyricsService.lyrics(for: track)
            isLoading = false
        }
    }

    private func synced(_ lines: [LyricLine]) -> some View {
        let currentID = lines.last(where: { $0.time <= clock.elapsed + 0.25 })?.id
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(lines) { line in
                        Button {
                            playback.seek(to: line.time)
                            Haptics.selection()
                        } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(line.id == currentID ? DesignSystem.AppColors.primaryText : DesignSystem.AppColors.secondaryText.opacity(0.55))
                                .scaleEffect(line.id == currentID ? 1.0 : 0.96, anchor: .leading)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                        .accessibilityLabel(line.text)
                        .accessibilityHint("Plays from this line")
                    }
                }
                .padding(.vertical, 40)
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
            .onChange(of: currentID) {
                guard let currentID else { return }
                withAnimation(DesignSystem.Motion.spring) { proxy.scrollTo(currentID, anchor: .center) }
            }
        }
    }
}

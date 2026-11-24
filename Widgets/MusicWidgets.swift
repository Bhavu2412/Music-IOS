import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct NowPlayingWidgetEntry: TimelineEntry {
    var date: Date
    let state: WidgetTrackState?
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingWidgetEntry

    var body: some View {
        // Group so the modifiers below apply to whichever layout the switch picks.
        Group {
        switch family {
        case .systemSmall:
            ZStack(alignment: .bottomLeading) {
                artwork
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Spacer(minLength: 0)
                    Text(entry.state?.title ?? "Nothing Playing")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(entry.state?.artist ?? "Open Music")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if let state = entry.state {
                    Button(intent: PlayPauseIntent()) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 12) {
                artwork
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                trackInfo
                controls
                    .frame(maxWidth: .infinity)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                artwork
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.state?.title ?? "Music")
                        .font(.headline)
                        .lineLimit(1)
                    Text(entry.state?.artist ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: entry.state?.isPlaying == true ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
            }
        default:
            HStack(spacing: 14) {
                artwork
                    .frame(width: 118, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    trackInfo
                    controls
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
        }
        }
        .tint(Color(red: 0.486, green: 0.514, blue: 1))
        // Text sits on dark, artwork-tinted glass, so render it light in both appearances.
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) {
            ZStack {
                Color.black
                if let data = entry.state?.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 28)
                        .opacity(0.6)
                }
            }
        }
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.state?.title ?? "Nothing Playing")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(1)
            Text(entry.state?.artist ?? "Open Music")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button(intent: PreviousTrackIntent()) {
                Image(systemName: "backward.fill")
            }
            .accessibilityLabel("Previous song")
            Button(intent: PlayPauseIntent()) {
                Image(systemName: entry.state?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
            }
            .accessibilityLabel(entry.state?.isPlaying == true ? "Pause" : "Play")
            Button(intent: NextTrackIntent()) {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel("Next song")
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.tint)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = entry.state?.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }
}

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("An artwork-forward view of the song currently playing.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingWidgetEntry {
        NowPlayingWidgetEntry(date: .now, state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingWidgetEntry) -> Void) {
        completion(NowPlayingWidgetEntry(date: .now, state: WidgetDataService.shared.loadNowPlayingState()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingWidgetEntry>) -> Void) {
        let entry = NowPlayingWidgetEntry(date: .now, state: WidgetDataService.shared.loadNowPlayingState())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

/// Reads the play state the app shares, so the control shows Play or Pause.
@available(iOS 18.0, *)
struct NowPlayingValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetDataService.shared.loadNowPlayingState()?.isPlaying ?? false
    }
}

/// Control Center / Lock Screen / Action button controls (iOS 18+).
@available(iOS 18.0, *)
struct PlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "MusicPlayPause", provider: NowPlayingValueProvider()) { isPlaying in
            ControlWidgetButton(action: PlayPauseIntent()) {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
            }
        }
        .displayName("Play / Pause")
        .description("Play or pause Music.")
    }
}

@available(iOS 18.0, *)
struct NextTrackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "MusicNextTrack") {
            ControlWidgetButton(action: NextTrackIntent()) {
                Label("Next Song", systemImage: "forward.fill")
            }
        }
        .displayName("Next Song")
        .description("Skip to the next song in Music.")
    }
}

@available(iOS 18.0, *)
struct PreviousTrackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "MusicPreviousTrack") {
            ControlWidgetButton(action: PreviousTrackIntent()) {
                Label("Previous Song", systemImage: "backward.fill")
            }
        }
        .displayName("Previous Song")
        .description("Go back to the previous song in Music.")
    }
}

@main
struct MusicWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        if #available(iOS 18.0, *) {
            PlayPauseControl()
            NextTrackControl()
            PreviousTrackControl()
        }
    }
}

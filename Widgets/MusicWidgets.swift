import ActivityKit
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
        .tint(Color(red: 0.486, green: 0.514, blue: 1))
        .containerBackground(for: .widget) {
            Color.black.opacity(0.01)
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

struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(context.state.track).font(.headline).lineLimit(1)
                    Text(context.state.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let data = context.state.artworkData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 48, height: 48)
                            .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.track)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 28) {
                        Button(intent: PreviousTrackIntent()) {
                            Image(systemName: "backward.fill")
                                .font(.title3)
                        }
                        Button(intent: PlayPauseIntent()) {
                            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2.weight(.bold))
                        }
                        Button(intent: NextTrackIntent()) {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .padding(.top, 6)
                }
            } compactLeading: {
                if let data = context.state.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                }
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
            } minimal: {
                if let data = context.state.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "music.note")
                }
            }
        }
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

/// Control Center / Lock Screen / Action button control (iOS 18+).
@available(iOS 18.0, *)
struct PlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "MusicPlayPause") {
            ControlWidgetButton(action: PlayPauseIntent()) {
                Label("Play / Pause", systemImage: "playpause.fill")
            }
        }
        .displayName("Play / Pause")
        .description("Play or pause Music.")
    }
}

@main
struct MusicWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        NowPlayingLiveActivity()
        if #available(iOS 18.0, *) {
            PlayPauseControl()
        }
    }
}

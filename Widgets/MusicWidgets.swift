import ActivityKit
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
        HStack(spacing: 12) {
            if family != .systemSmall {
                artwork.frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 6) {
                if family == .systemSmall {
                    artwork.frame(width: 44, height: 44)
                    Spacer(minLength: 0)
                }
                Label(entry.state?.isPlaying == true ? "Playing" : "Music",
                      systemImage: entry.state?.isPlaying == true ? "waveform" : "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let state = entry.state {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(state.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Nothing playing")
                        .font(.headline)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
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
        .description("Shows the current track.")
        .supportedFamilies([.systemSmall, .systemMedium])
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
                    Image(systemName: "music.note").font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.track).font(.headline).lineLimit(1)
                        Text(context.state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
            } minimal: {
                Image(systemName: "music.note")
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

@main
struct MusicWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        NowPlayingLiveActivity()
    }
}

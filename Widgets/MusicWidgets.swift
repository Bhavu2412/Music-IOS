import SwiftUI
import WidgetKit

struct NowPlayingWidgetEntry: TimelineEntry {
    var date: Date
    let state: WidgetTrackState?
}

struct NowPlayingWidgetView: View {
    let entry: NowPlayingWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Music")
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
        .padding()
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}

@main
struct MusicWidgets: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
    }
}

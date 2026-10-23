import SwiftUI
import WidgetKit

struct WatchEntry: TimelineEntry {
    let date: Date
    let snap: SharedSnapshot
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: .now, snap: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) { completion(WatchEntry(date: .now, snap: WatchSnapshot.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        completion(Timeline(entries: [WatchEntry(date: .now, snap: WatchSnapshot.load())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

enum WatchSnapshot {
    static func load() -> SharedSnapshot {
        guard let d = UserDefaults(suiteName: "group.nl.lrvdlinden.devtools.watch")?.data(forKey: "watchSnapshot"),
              let val = try? JSONDecoder().decode(SharedSnapshot.self, from: d) else { return .placeholder }
        return val
    }
}

struct ComplicationView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) var family

    private var headline: String {
        if let d = entry.snap.downloads { return d.formatted(.number.notation(.compactName)) }
        return "\(entry.snap.apps.count)"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.snap.downloads == nil ? "square.grid.2x2.fill" : "arrow.down")
                        .font(.caption2)
                    Text(headline).font(.headline).minimumScaleFactor(0.6)
                }
            }
            .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Text("DevTools · \(entry.snap.liveCount) live · \(entry.snap.inReview) review")
        case .accessoryCorner:
            Text(headline)
                .widgetLabel { Text("DevTools") }
                .containerBackground(.clear, for: .widget)
        default:
            VStack(alignment: .leading, spacing: 1) {
                Label("DevTools", systemImage: "square.grid.2x2.fill").font(.caption2.weight(.semibold))
                if let d = entry.snap.downloads {
                    Text("\(d.formatted()) downloads").font(.headline)
                } else {
                    Text("\(entry.snap.apps.count) apps").font(.headline)
                }
                Text("\(entry.snap.liveCount) live · \(entry.snap.inReview) in review").font(.caption2)
            }
            .containerBackground(.clear, for: .widget)
        }
    }
}

@main
struct DevWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevToolsWatchComplications", provider: WatchProvider()) { ComplicationView(entry: $0) }
            .configurationDisplayName("DevTools")
            .description("Downloads en app-status")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

import SwiftUI
import WidgetKit

/// Watch face complications: downloads, 7-day change and apps in review.
/// They read the summary the watch app stored in its App Group (like HomeyDev).
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct ComplicationProvider: TimelineProvider {
    private static func stored() -> SharedSnapshot? {
        let s = SharedSnapshot.load(suite: SharedSnapshot.watchSuite, key: "watchSnapshot")
        return s.apps.isEmpty ? nil : s
    }

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: SharedSnapshot(updated: .now, apps: [], downloads: 1240, downloadsRange: "30d"))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: Self.stored() ?? placeholder(in: context).snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(date: .now, snapshot: Self.stored())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

private enum CFmt {
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func signed(_ n: Int) -> String { n > 0 ? "+\(compact(n))" : n < 0 ? "−\(compact(-n))" : "±0" }
    static func headline(_ s: SharedSnapshot?) -> String {
        guard let s else { return "–" }
        if let d = s.downloads { return compact(d) }
        return "\(s.apps.count)"
    }
}

struct DownloadsComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: s?.downloads == nil ? "square.grid.2x2.fill" : "arrow.down.circle.fill").font(.system(size: 11))
                    Text(CFmt.headline(s))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                }
            }
            .widgetAccentable()
        case .accessoryCorner:
            Text(CFmt.headline(s))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .widgetLabel {
                    Text(s?.delta7.map { "\(CFmt.signed($0)) 7d" } ?? "DevTools")
                }
        case .accessoryInline:
            if let s {
                Text("⬇︎ \(CFmt.headline(s))\(s.inReview == 0 ? "" : " · \(s.inReview) review")")
            } else {
                Text("DevTools")
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: 11, weight: .bold))
                    Text("DevTools").font(.system(size: 12, weight: .semibold))
                }
                .widgetAccentable()
                if let s {
                    if let d = s.downloads {
                        Text(d.formatted(.number))
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("\(s.apps.count) apps").font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    HStack(spacing: 6) {
                        if let d7 = s.delta7 { Text("\(CFmt.signed(d7)) 7d") }
                        Text("✓ \(s.liveCount)")
                        if s.inReview > 0 { Text("⏳ \(s.inReview)") }
                    }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                } else {
                    Text("Open de iPhone-app").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DownloadsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevToolsWatchComplications", provider: ComplicationProvider()) { entry in
            DownloadsComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Downloads")
        .description("Downloads, groei en apps in review.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct DevWatchWidgets: WidgetBundle {
    var body: some Widget {
        DownloadsComplication()
    }
}

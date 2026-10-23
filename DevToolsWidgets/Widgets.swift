import SwiftUI
import UIKit
import WidgetKit
import Charts

struct DevEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot
}

struct DevProvider: TimelineProvider {
    func placeholder(in context: Context) -> DevEntry { DevEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (DevEntry) -> Void) {
        let s = SharedSnapshot.load()
        completion(DevEntry(date: .now, snapshot: context.isPreview && s.apps.isEmpty ? .sample : s))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DevEntry>) -> Void) {
        completion(Timeline(entries: [DevEntry(date: .now, snapshot: SharedSnapshot.load())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

extension SharedSnapshot {
    static let sample = SharedSnapshot(
        updated: .now,
        apps: [
            WidgetAppSummary(id: "1", name: "Bingr", version: "1.0.0", state: "READY_FOR_SALE", liveVersion: "1.0.0", downloads: 1240),
            WidgetAppSummary(id: "2", name: "Pitwall", version: "1.1", state: "IN_REVIEW", liveVersion: "1.0", pendingVersion: "1.1", pendingState: "IN_REVIEW", downloads: 380),
            WidgetAppSummary(id: "3", name: "TVArt", version: "2.0", state: "PREPARE_FOR_SUBMISSION", downloads: 95)
        ],
        accountName: "PixelForges", downloads: 1715, downloadsRange: "30d",
        series: [30, 42, 38, 55, 61, 48, 70, 66, 74, 90, 82, 95], proceeds: 412.5, currency: "EUR")
}

enum WidgetPalette {
    static let accent = Color(red: 0.04, green: 0.42, blue: 1.0)
    static let cyan = Color(red: 0.08, green: 0.72, blue: 0.9)
    static let live = Color(red: 0.13, green: 0.68, blue: 0.33)
    static let review = Color(red: 0.95, green: 0.55, blue: 0.0)

    static func color(for state: String) -> Color {
        switch state {
        case "READY_FOR_SALE": return live
        case "READY_FOR_DISTRIBUTION": return cyan
        case "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW": return review
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": return .red
        case "PENDING_DEVELOPER_RELEASE": return .purple
        default: return .secondary
        }
    }
}

struct WidgetIcon: View {
    let app: WidgetAppSummary
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let url = SharedSnapshot.iconURL(for: app.id), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [WidgetPalette.accent, WidgetPalette.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(String(app.name.prefix(1))).font(.system(size: size * 0.45, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

struct DevWidgetView: View {
    let entry: DevEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .systemSmall: small(s)
        case .systemLarge: large(s)
        default: medium(s)
        }
    }

    private func header(_ s: SharedSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.2x2.fill").foregroundStyle(WidgetPalette.accent)
            Text("DevTools").font(.caption.weight(.bold))
            Spacer(minLength: 0)
        }
    }

    private func small(_ s: SharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(s)
            Spacer(minLength: 0)
            if let d = s.downloads {
                Text(d.formatted(.number.notation(.compactName))).font(.system(size: 34, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                Text("downloads · \(s.downloadsRange ?? "")").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("\(s.apps.count)").font(.system(size: 36, weight: .bold, design: .rounded))
                Text("apps").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Label("\(s.liveCount)", systemImage: "checkmark.seal.fill").foregroundStyle(WidgetPalette.live)
                Label("\(s.inReview)", systemImage: "hourglass").foregroundStyle(s.inReview > 0 ? WidgetPalette.review : .secondary)
            }
            .font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
    }

    private func medium(_ s: SharedSnapshot) -> some View {
        HStack(spacing: 14) {
            small(s).frame(maxWidth: 120)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(s.apps.prefix(4)) { app in appLine(app) }
                if s.apps.isEmpty { Text("Open DevTools om je apps te laden").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
    }

    private func large(_ s: SharedSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header(s)
                Text(s.updated, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                stat("\(s.apps.count)", "apps", .primary)
                stat("\(s.liveCount)", "live", WidgetPalette.live)
                stat("\(s.inReview)", "review", WidgetPalette.review)
                if let d = s.downloads { stat(d.formatted(.number.notation(.compactName)), "downloads", WidgetPalette.accent) }
            }
            if let series = s.series, series.count > 2 {
                Spark(values: series).frame(height: 54)
            }
            Divider()
            ForEach(s.apps.prefix(7)) { app in appLine(app) }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func appLine(_ app: WidgetAppSummary) -> some View {
        HStack(spacing: 8) {
            WidgetIcon(app: app, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name).font(.caption.weight(.semibold)).lineLimit(1)
                Text(app.statusLabel + (app.pendingVersion.map { " · \($0)" } ?? (app.liveVersion.map { " · \($0)" } ?? "")))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WidgetPalette.color(for: app.state))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if let d = app.downloads { Text(d.formatted(.number.notation(.compactName))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
        }
    }
}

struct Spark: View {
    let values: [Int]
    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("i", item.offset), y: .value("v", item.element))
                .foregroundStyle(LinearGradient(colors: [WidgetPalette.accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("i", item.offset), y: .value("v", item.element))
                .foregroundStyle(WidgetPalette.accent)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

struct AppPortfolioWidget: Widget {
    let kind = "AppPortfolioWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DevProvider()) { DevWidgetView(entry: $0) }
            .configurationDisplayName("DevTools overzicht")
            .description("Je apps met icoon, status en downloads.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DownloadsWidgetView: View {
    let entry: DevEntry
    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Downloads", systemImage: "arrow.down.circle.fill").font(.caption.weight(.bold)).foregroundStyle(WidgetPalette.accent)
                Spacer()
                Text(s.downloadsRange ?? "").font(.caption2).foregroundStyle(.secondary)
            }
            if let d = s.downloads {
                Text(d.formatted(.number)).font(.system(size: 30, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                if let series = s.series, series.count > 2 { Spark(values: series) }
                if let p = s.proceeds, let c = s.currency {
                    Text(p.formatted(.currency(code: c))).font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.live)
                }
            } else {
                Spacer()
                Text("Vul je vendornummer in de app in om downloads te zien.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
    }
}

struct DownloadsWidget: Widget {
    let kind = "DevDownloadsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DevProvider()) { DownloadsWidgetView(entry: $0) }
            .configurationDisplayName("Downloads")
            .description("Downloads en opbrengst met trendlijn.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ReviewWidget: Widget {
    let kind = "DevReviewWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DevProvider()) { entry in
            let review = entry.snapshot.apps.filter { ["WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW", "PENDING_DEVELOPER_RELEASE", "REJECTED", "METADATA_REJECTED"].contains($0.pendingState ?? $0.state) }
            VStack(alignment: .leading, spacing: 7) {
                Label("App Review", systemImage: "hourglass").font(.caption.weight(.bold)).foregroundStyle(WidgetPalette.review)
                Text("\(entry.snapshot.inReview)").font(.system(size: 30, weight: .bold, design: .rounded))
                ForEach(review.prefix(3)) { a in
                    HStack(spacing: 6) {
                        WidgetIcon(app: a, size: 16)
                        Text(a.name).font(.caption2.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(SharedSnapshot.label(for: a.pendingState ?? a.state)).font(.system(size: 9)).foregroundStyle(WidgetPalette.color(for: a.pendingState ?? a.state)).lineLimit(1)
                    }
                }
                if review.isEmpty { Text("Niets in review").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color(UIColor.systemBackground) }
        }
        .configurationDisplayName("App Review")
        .description("Apps die bij Apple in review zijn.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DevWidgets: WidgetBundle {
    var body: some Widget {
        AppPortfolioWidget()
        DownloadsWidget()
        ReviewWidget()
    }
}

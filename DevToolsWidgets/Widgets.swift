import SwiftUI
import UIKit
import WidgetKit
import Charts
import AppIntents

// MARK: - Bundle (same set-up as HomeyDev: Downloads, Top apps, Status)

@main
struct DevWidgets: WidgetBundle {
    var body: some Widget {
        DownloadsWidget()
        TopAppsWidget()
        StatusWidget()
    }
}

// MARK: - App picker (widget configuration)

struct AppChoice: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static var defaultQuery = AppChoiceQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AppChoiceQuery: EntityQuery {
    func entities(for identifiers: [AppChoice.ID]) async throws -> [AppChoice] {
        let apps = SharedSnapshot.load().apps
        return identifiers.compactMap { id in apps.first { $0.id == id }.map { AppChoice(id: $0.id, name: $0.name) } }
    }

    func suggestedEntities() async throws -> [AppChoice] {
        SharedSnapshot.load().apps.map { AppChoice(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> AppChoice? { nil }
}

struct SelectAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kies een app"
    static var description = IntentDescription("Toon de downloads van één app, of laat leeg voor al je apps.")

    @Parameter(title: "App")
    var app: AppChoice?
}

// MARK: - Timelines

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot
    var appId: String? = nil
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let s = SharedSnapshot.load()
        completion(SnapshotEntry(date: .now, snapshot: s.apps.isEmpty ? .sample : s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: SharedSnapshot.load())], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct AppIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }

    func snapshot(for configuration: SelectAppIntent, in context: Context) async -> SnapshotEntry {
        let s = SharedSnapshot.load()
        return SnapshotEntry(date: .now, snapshot: s.apps.isEmpty ? .sample : s, appId: configuration.app?.id)
    }

    func timeline(for configuration: SelectAppIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let entry = SnapshotEntry(date: .now, snapshot: SharedSnapshot.load(), appId: configuration.app?.id)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

extension SharedSnapshot {
    static var sample: SharedSnapshot {
        let cal = Calendar.current
        func hist(_ base: Int) -> [HistoryPoint] {
            (0..<30).map { i in
                HistoryPoint(date: cal.date(byAdding: .day, value: i - 30, to: .now) ?? .now,
                             value: base + Int(Double(base) * 0.4 * sin(Double(i) / 3)) + i)
            }
        }
        let a = hist(40), b = hist(14), c = hist(5)
        var total: [HistoryPoint] = []
        for i in a.indices { total.append(HistoryPoint(date: a[i].date, value: a[i].value + b[i].value + c[i].value)) }
        return SharedSnapshot(
            updated: .now,
            apps: [
                WidgetAppSummary(id: "1", name: "Bingr", version: "1.0.0", state: "READY_FOR_SALE", liveVersion: "1.0.0", downloads: a.reduce(0) { $0 + $1.value }, build: "138", rating: 4.8, ratingCount: 120, proceeds: 312, updates: 420, history: a),
                WidgetAppSummary(id: "2", name: "Pitwall", version: "1.1", state: "IN_REVIEW", liveVersion: "1.0", pendingVersion: "1.1", pendingState: "IN_REVIEW", downloads: b.reduce(0) { $0 + $1.value }, build: "42", rating: 4.6, ratingCount: 31, proceeds: 80, history: b),
                WidgetAppSummary(id: "3", name: "TVArt", version: "2.0", state: "READY_FOR_DISTRIBUTION", pendingVersion: "2.0", pendingState: "READY_FOR_DISTRIBUTION", downloads: c.reduce(0) { $0 + $1.value }, build: "12", history: c)
            ],
            accountName: "PixelForges", downloads: total.reduce(0) { $0 + $1.value }, downloadsRange: "30d",
            proceeds: 392, currency: "EUR", history: total, updates: 640)
    }
}

// MARK: - Shared styling

enum W {
    static let accent = Color(red: 0.04, green: 0.42, blue: 1.0)
    static let cyan = Color(red: 0.08, green: 0.72, blue: 0.9)
    static let live = Color(red: 0.13, green: 0.68, blue: 0.33)
    static let review = Color(red: 0.95, green: 0.55, blue: 0.0)
    static let pending = Color(red: 0.48, green: 0.36, blue: 0.98)

    static func number(_ n: Int) -> String { n.formatted(.number) }
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func signed(_ n: Int) -> String { n > 0 ? "+\(compact(n))" : n < 0 ? "−\(compact(-n))" : "±0" }
    static func rating(_ r: Double?) -> String { r.map { String(format: "%.1f", $0) } ?? "—" }
    static func money(_ v: Double?, _ c: String?) -> String {
        guard let v else { return "—" }
        guard let c, !c.isEmpty else { return String(format: "%.0f", v) }
        return v.formatted(.currency(code: c).precision(.fractionLength(0)))
    }

    static func color(for state: String) -> Color {
        switch state {
        case "READY_FOR_SALE": return live
        case "READY_FOR_DISTRIBUTION": return cyan
        case "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW", "MISSING_EXPORT_COMPLIANCE": return review
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": return .red
        case "PENDING_DEVELOPER_RELEASE": return pending
        default: return .secondary
        }
    }
}

struct WidgetHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image("DevLogo").resizable().scaledToFit().frame(width: 14, height: 14)
            Text(LS(title)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if let trailing { Text(trailing).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1) }
        }
    }
}

struct AppIcon: View {
    let app: WidgetAppSummary
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url = SharedSnapshot.iconURL(for: app.id), let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [W.accent, W.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(String(app.name.prefix(1))).font(.system(size: size * 0.45, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

struct DeltaLabel: View {
    let delta: Int?
    var suffix: String? = nil
    var body: some View {
        if let delta {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "equal")
                Text(W.signed(delta))
                if let suffix { Text(suffix).foregroundStyle(.secondary).fontWeight(.regular) }
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(delta > 0 ? Color.green : delta < 0 ? Color.red : Color.secondary)
            .lineLimit(1)
        }
    }
}

/// Homey Insights-style chart: smooth line, gradient fill, min/max labels and a dot on the latest value.
struct InsightsChart: View {
    let points: [HistoryPoint]
    var color: Color = W.accent
    var showAxis = true
    var days = 30

    var body: some View {
        let data = Array(points.suffix(days))
        if data.count >= 2 {
            let lo = data.map(\.value).min() ?? 0
            let hi = data.map(\.value).max() ?? 1
            let pad = max(Double(hi - lo) * 0.15, 1)
            Chart(data, id: \.date) { p in
                AreaMark(x: .value("Dag", p.date), yStart: .value("Min", Double(lo) - pad), yEnd: .value("Downloads", Double(p.value)))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Dag", p.date), y: .value("Downloads", Double(p.value)))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                if p.date == data.last?.date {
                    PointMark(x: .value("Dag", p.date), y: .value("Downloads", Double(p.value)))
                        .foregroundStyle(color)
                        .symbolSize(28)
                }
            }
            .chartYScale(domain: (Double(lo) - pad)...(Double(hi) + pad))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [Double(lo), Double(hi)]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text(W.compact(Int(d))).font(.system(size: 8)) }
                    }
                }
            }
            .chartYAxis(showAxis ? .visible : .hidden)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                Text("Vul je vendornummer in voor downloads").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(4)
            }
        }
    }
}

struct MiniSparkline: View {
    let points: [HistoryPoint]
    var color: Color = W.accent
    var body: some View {
        let data = Array(points.suffix(30))
        if data.count >= 2 {
            Chart(data, id: \.date) { p in
                LineMark(x: .value("Dag", p.date), y: .value("Downloads", Double(p.value)))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
        } else {
            Color.clear
        }
    }
}

struct StatChip: View {
    let icon: String
    let value: String
    var tint: Color = W.accent
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 9, weight: .bold))
            Text(value).font(.caption2.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image("DevLogo").resizable().scaledToFit().frame(width: 30, height: 30)
            Text("Open DevTools om je gegevens te laden.").font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 1. Downloads (configurable per app)

struct DownloadsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DevDownloadsWidget", intent: SelectAppIntent.self, provider: AppIntentProvider()) { entry in
            DownloadsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Downloads")
        .description("Downloads met de Insights-grafiek van één app of al je apps. Houd ingedrukt → Wijzig widget om een app te kiezen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DownloadsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        if s.apps.isEmpty {
            EmptyWidgetView()
        } else {
            content(s, app: s.app(entry.appId))
        }
    }

    @ViewBuilder
    private func content(_ s: SharedSnapshot, app: WidgetAppSummary?) -> some View {
        let title = app?.name ?? "Alle apps"
        let downloads: Int? = app != nil ? app?.downloads : s.downloads
        let history: [HistoryPoint] = app?.series ?? s.totalHistory
        let d7: Int? = app != nil ? app?.delta7 : s.delta7
        let range = s.downloadsRange ?? ""
        let proceeds: Double? = app != nil ? app?.proceeds : s.proceeds
        let updates: Int = (app != nil ? app?.updates : s.updates) ?? 0
        let rating: Double? = app != nil ? app?.rating : s.averageRating
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 3) {
                titleRow(app, title, iconSize: 18)
                Text(downloads.map { W.number($0) } ?? "—")
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                if d7 != nil { DeltaLabel(delta: d7, suffix: "7d") } else { Text("downloads · \(range)").font(.caption2).foregroundStyle(.secondary) }
                InsightsChart(points: history, showAxis: false).frame(maxHeight: .infinity)
            }

        case .systemMedium:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    titleRow(app, title, iconSize: 20)
                    Text(downloads.map { W.number($0) } ?? "—")
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text("downloads · \(range)").font(.caption2).foregroundStyle(.secondary)
                    DeltaLabel(delta: d7, suffix: "7d")
                    Spacer(minLength: 0)
                    StatChip(icon: "eurosign.circle.fill", value: W.money(proceeds, s.currency), tint: W.live)
                }
                .frame(width: 128, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        StatChip(icon: "star.fill", value: W.rating(rating), tint: .yellow)
                        StatChip(icon: "arrow.triangle.2.circlepath", value: W.compact(updates), tint: W.pending)
                        if let app {
                            StatChip(icon: "hammer.fill", value: app.build ?? "—", tint: W.cyan)
                        } else {
                            StatChip(icon: "hourglass", value: "\(s.inReview)", tint: s.inReview > 0 ? W.review : .secondary)
                        }
                    }
                    InsightsChart(points: history)
                }
            }

        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let app { AppIcon(app: app, size: 30) } else { Image("DevLogo").resizable().frame(width: 26, height: 26) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(LS(title)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let app {
                            Text(app.statusLabel + (app.liveVersion.map { " · v\($0)" } ?? ""))
                                .font(.caption2).foregroundStyle(W.color(for: app.state)).lineLimit(1)
                        } else {
                            Text(s.accountName ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(downloads.map { W.number($0) } ?? "—").font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        HStack(spacing: 6) {
                            DeltaLabel(delta: d7, suffix: "7d")
                            Text(range).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                InsightsChart(points: history, days: 90).frame(maxHeight: .infinity)
                HStack {
                    StatChip(icon: "star.fill", value: W.rating(rating), tint: .yellow)
                    Spacer()
                    StatChip(icon: "eurosign.circle.fill", value: W.money(proceeds, s.currency), tint: W.live)
                    Spacer()
                    StatChip(icon: "arrow.triangle.2.circlepath", value: W.compact(updates), tint: W.pending)
                    Spacer()
                    StatChip(icon: "checkmark.seal.fill", value: "\(s.liveCount) live", tint: W.live)
                }
                if app == nil, !s.topApps.isEmpty {
                    Divider()
                    Text("Meeste downloads").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(s.topApps.prefix(3)) { m in
                        HStack(spacing: 6) {
                            AppIcon(app: m, size: 16)
                            Text(m.name).font(.caption2).lineLimit(1)
                            Spacer()
                            Text(W.compact(m.downloads ?? 0)).font(.caption2.monospacedDigit().weight(.semibold))
                            DeltaLabel(delta: m.delta7)
                        }
                    }
                }
            }
        }
    }

    private func titleRow(_ app: WidgetAppSummary?, _ title: String, iconSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            if let app {
                AppIcon(app: app, size: iconSize)
            } else {
                Image("DevLogo").resizable().frame(width: iconSize - 2, height: iconSize - 2)
            }
            Text(LS(title)).font(.caption.weight(.semibold)).lineLimit(1)
        }
    }
}

// MARK: - 2. Top apps

struct TopAppsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevTopAppsWidget", provider: SnapshotProvider()) { entry in
            TopAppsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Top apps")
        .description("Je apps met icoon, trend, downloads, rating en status.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TopAppsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        if s.apps.isEmpty {
            EmptyWidgetView()
        } else {
            let large = family == .systemLarge
            let apps = Array(s.topApps.prefix(large ? 6 : 3))
            VStack(alignment: .leading, spacing: large ? 9 : 6) {
                WidgetHeader(title: "Top apps", trailing: headerTrailing(s))
                ForEach(apps) { app in row(app, large: large) }
                if large {
                    Spacer(minLength: 0)
                    HStack {
                        StatChip(icon: "checkmark.seal.fill", value: "\(s.liveCount) live", tint: W.live)
                        Spacer()
                        StatChip(icon: "hourglass", value: "\(s.inReview) in review", tint: W.review)
                        Spacer()
                        StatChip(icon: "eurosign.circle.fill", value: W.money(s.proceeds, s.currency), tint: W.live)
                    }
                }
            }
        }
    }

    private func headerTrailing(_ s: SharedSnapshot) -> String {
        if let d = s.downloads { return "\(W.compact(d)) · \(s.downloadsRange ?? "")" }
        return "\(s.apps.count) apps"
    }

    private func row(_ app: WidgetAppSummary, large: Bool) -> some View {
        HStack(spacing: 8) {
            AppIcon(app: app, size: large ? 32 : 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.name).font(.caption.weight(.semibold)).lineLimit(1)
                    if app.inReview { Image(systemName: "hourglass").font(.system(size: 9)).foregroundStyle(W.review) }
                    if app.needsAttention { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)).foregroundStyle(W.pending) }
                }
                HStack(spacing: 6) {
                    if app.isLive {
                        Text("v\(app.liveVersion ?? app.version)").foregroundStyle(W.live)
                    } else {
                        Text(app.statusLabel).foregroundStyle(W.color(for: app.state))
                    }
                    if let r = app.rating, (app.ratingCount ?? 0) > 0 { Text("★ \(W.rating(r))").foregroundStyle(.yellow) }
                    if large, let b = app.build { Text("build \(b)").foregroundStyle(.secondary) }
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            MiniSparkline(points: app.series)
                .frame(width: large ? 64 : 48, height: large ? 24 : 18)
            VStack(alignment: .trailing, spacing: 0) {
                Text(app.downloads.map { W.compact($0) } ?? "—").font(.caption.weight(.bold).monospacedDigit())
                DeltaLabel(delta: app.delta7)
            }
            .frame(minWidth: 44, alignment: .trailing)
        }
    }
}

// MARK: - 3. Status (review, release, attention)

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevStatusWidget", provider: SnapshotProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("WidgetBackground") }
        }
        .configurationDisplayName("Review & status")
        .description("App Review, klaar voor release en wat aandacht nodig heeft in één oogopslag.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StatusWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        let rejected = s.apps.filter { ["REJECTED", "METADATA_REJECTED", "INVALID_BINARY"].contains($0.activeState) }.count
        let attentionTint: Color = s.attentionApps.isEmpty ? .secondary : W.pending
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Status")
                counter("checkmark.seal.fill", W.live, s.liveCount, "Live")
                counter("hourglass", W.review, s.inReview, "In review")
                counter("exclamationmark.circle.fill", attentionTint, s.attentionApps.count, "Aandacht")
                Spacer(minLength: 0)
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Status")
                    counter("checkmark.seal.fill", W.live, s.liveCount, "Live")
                    counter("hourglass", W.review, s.inReview, "In review")
                    counter("exclamationmark.circle.fill", attentionTint, s.attentionApps.count, "Aandacht")
                }
                .frame(width: 118, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    reviewList(s, max: 2)
                    attentionList(s, max: 2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(title: "Developer-status", trailing: s.accountName)
                HStack(spacing: 8) {
                    tile("checkmark.seal.fill", W.live, "\(s.liveCount)", "Live")
                    tile("hourglass", W.review, "\(s.inReview)", "In review")
                    tile("xmark.octagon.fill", rejected > 0 ? Color.red : Color.secondary, "\(rejected)", "Afgewezen")
                    tile("star.fill", .yellow, W.rating(s.averageRating), "Rating")
                }
                reviewList(s, max: 3)
                attentionList(s, max: 3)
                Spacer(minLength: 0)
                HStack {
                    Text("Bijgewerkt").foregroundStyle(.secondary)
                    Text(s.updated, style: .relative).foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func reviewList(_ s: SharedSnapshot, max: Int) -> some View {
        Text("In review").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        if s.inReviewApps.isEmpty {
            Label("Niets in review", systemImage: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
        }
        ForEach(s.inReviewApps.prefix(max)) { app in
            HStack(spacing: 6) {
                AppIcon(app: app, size: 18)
                Text(app.name).font(.caption2.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 2)
                Text("v\(app.pendingVersion ?? app.version)").font(.caption2.monospacedDigit()).foregroundStyle(W.review)
            }
        }
    }

    @ViewBuilder
    private func attentionList(_ s: SharedSnapshot, max: Int) -> some View {
        Text("Aandacht nodig").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        if s.attentionApps.isEmpty {
            Label("Alles in orde", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
        }
        ForEach(s.attentionApps.prefix(max)) { app in
            attentionRow(app)
        }
    }

    private func attentionRow(_ app: WidgetAppSummary) -> some View {
        let state = app.buildState == "MISSING_EXPORT_COMPLIANCE" ? "MISSING_EXPORT_COMPLIANCE" : app.activeState
        return HStack(spacing: 6) {
            AppIcon(app: app, size: 18)
            Text(app.name).font(.caption2.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 2)
            Text(SharedSnapshot.label(for: state)).font(.system(size: 9, weight: .semibold)).foregroundStyle(W.color(for: state)).lineLimit(1)
        }
    }

    private func counter(_ icon: String, _ tint: Color, _ value: Int, _ label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: -1) {
                Text("\(value)").font(.subheadline.weight(.bold).monospacedDigit())
                Text(LS(label)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func tile(_ icon: String, _ tint: Color, _ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.caption.weight(.bold)).foregroundStyle(tint)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(LS(label)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) { DownloadsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview(as: .systemMedium) { DownloadsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview(as: .systemLarge) { TopAppsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview(as: .systemLarge) { StatusWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }

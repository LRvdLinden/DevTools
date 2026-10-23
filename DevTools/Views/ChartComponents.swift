import SwiftUI
import Charts

enum TrendMetric: String, CaseIterable, Identifiable {
    case installs, downloads, updates, iap, proceeds
    var id: String { rawValue }

    var label: String {
        switch self {
        case .installs: return L("Installaties")
        case .downloads: return L("Nieuwe downloads")
        case .updates: return L("Updates")
        case .iap: return L("In-app")
        case .proceeds: return L("Opbrengst")
        }
    }

    var short: String {
        switch self {
        case .installs: return L("Install.")
        case .downloads: return L("Nieuw")
        case .updates: return L("Updates")
        case .iap: return "IAP"
        case .proceeds: return "€"
        }
    }

    var tint: Color {
        switch self {
        case .installs: return Theme.accent
        case .downloads: return Theme.cyan
        case .updates: return Theme.pending
        case .iap: return Theme.review
        case .proceeds: return Theme.live
        }
    }

    func value(_ p: SalesPoint) -> Double {
        switch self {
        case .installs: return Double(p.installs)
        case .downloads: return Double(p.downloads)
        case .updates: return Double(p.updates)
        case .iap: return Double(p.iap)
        case .proceeds: return p.proceeds
        }
    }

    func format(_ v: Double, currency: String) -> String {
        self == .proceeds ? Fmt.money(v, currency) : Fmt.number(Int(v.rounded()))
    }
}

/// Homey Insights-style chart: gradient area + smooth line, scrub to inspect a day.
struct TrendChart: View {
    let points: [SalesPoint]
    var metric: TrendMetric = .installs
    var currency: String = ""
    var height: CGFloat = 200
    var weekly = false

    @State private var selected: Date?

    private var selectedPoint: SalesPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        let tint = metric.tint
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Datum", p.date), y: .value(metric.label, metric.value(p)))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Datum", p.date), y: .value(metric.label, metric.value(p)))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let sel = selectedPoint {
                RuleMark(x: .value("Datum", sel.date))
                    .foregroundStyle(Theme.textSecondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        SelectionBubble(date: sel.date, value: metric.format(metric.value(sel), currency: currency), weekly: weekly)
                    }
                PointMark(x: .value("Datum", sel.date), y: .value(metric.label, metric.value(sel)))
                    .foregroundStyle(tint)
                    .symbolSize(70)
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Theme.separator)
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.clear)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: selectedPoint?.date)
    }
}

struct SelectionBubble: View {
    let date: Date
    let value: String
    var weekly = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.callout.weight(.bold).monospacedDigit())
            Text(weekly ? L("week t/m \(Fmt.day(date))") : Fmt.day(date)).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Card with title, range picker, metric chips, chart and min/avg/max row.
struct TrendCard: View {
    let title: String
    let summary: SalesSummary
    @Binding var range: SalesRange
    @Binding var metric: TrendMetric
    var loading = false
    var progress: Double = 0
    var metrics: [TrendMetric] = TrendMetric.allCases

    var body: some View {
        let values = summary.points.map { metric.value($0) }
        let total = values.reduce(0, +)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LS(title)).font(.headline)
                    Text(range.title).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if loading {
                    ProgressView(value: progress).frame(width: 60)
                } else {
                    Text(metric.format(total, currency: summary.currency))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(metric.tint)
                        .contentTransition(.numericText())
                }
            }
            Picker("Periode", selection: $range) {
                ForEach(SalesRange.allCases) { Text(LS($0.label)).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(metrics) { m in
                        Button { withAnimation(.snappy) { metric = m } } label: {
                            Text(LS(m.label))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(metric == m ? m.tint.opacity(0.18) : Theme.cardRaised, in: Capsule())
                                .foregroundStyle(metric == m ? m.tint : Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if summary.points.isEmpty {
                VStack(spacing: 8) {
                    if loading { ProgressView() } else {
                        Image(systemName: "chart.line.flattrend.xyaxis").font(.title).foregroundStyle(Theme.textSecondary)
                        Text("Nog geen gegevens in deze periode").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                TrendChart(points: summary.points, metric: metric, currency: summary.currency, weekly: range.weekly)
                HStack(spacing: 0) {
                    miniStat("Minimum", metric.format(values.min() ?? 0, currency: summary.currency))
                    Divider().frame(height: 26)
                    miniStat(range.weekly ? "Gem./week" : "Gem./dag", metric.format(values.isEmpty ? 0 : total / Double(values.count), currency: summary.currency))
                    Divider().frame(height: 26)
                    miniStat("Maximum", metric.format(values.max() ?? 0, currency: summary.currency))
                }
            }
        }
        .devCard()
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(LS(label)).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Horizontal stacked bars per app (new downloads + re-downloads), HomeyDev style.
struct AppDownloadBars: View {
    let items: [AppSales]
    let apps: [AppSummary]
    var limit = 8

    var body: some View {
        let shown = Array(items.filter { $0.installs > 0 }.prefix(limit))
        let maxValue = max(shown.map(\.installs).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(shown) { item in
                let app = apps.first { $0.id == item.id }
                NavigationLink {
                    AppDetailView(appID: item.id)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        AppIconView(url: app?.iconURL, size: 30, name: item.name)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(app?.name ?? item.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(Fmt.number(item.installs)).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(.primary)
                            }
                            BarTrack(first: item.downloads, second: item.redownloads, maxValue: maxValue)
                                .frame(height: 9)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(app == nil)
            }
            HStack(spacing: 16) {
                legend(Theme.accent, "Nieuw")
                legend(Theme.cyan, "Herdownload")
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(LS(title))
        }
    }
}

struct BarTrack: View {
    let first: Int
    let second: Int
    let maxValue: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fw = w * CGFloat(max(first, 0)) / CGFloat(maxValue)
            let sw = w * CGFloat(max(second, 0)) / CGFloat(maxValue)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                HStack(spacing: 2) {
                    if first > 0 { Rectangle().fill(Theme.accent).frame(width: max(fw, 3)) }
                    if second > 0 { Rectangle().fill(Theme.cyan).frame(width: max(sw, 3)) }
                }
                .clipShape(Capsule())
            }
        }
    }
}

/// Donut with legend (devices, ratings…).
struct ShareDonut: View {
    let items: [ShareItem]
    var limit = 5

    var body: some View {
        let top = Array(items.prefix(limit))
        let rest = items.dropFirst(limit).reduce(0) { $0 + $1.value }
        let all = rest > 0 ? top + [ShareItem(id: "_other", label: "Overig", value: rest)] : top
        let total = max(all.reduce(0) { $0 + $1.value }, 1)
        HStack(spacing: 18) {
            Chart(Array(all.enumerated()), id: \.element.id) { entry in
                SectorMark(angle: .value("Aantal", entry.element.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(Theme.series[entry.offset % Theme.series.count])
            }
            .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(all.enumerated()), id: \.element.id) { entry in
                    HStack(spacing: 8) {
                        Circle().fill(Theme.series[entry.offset % Theme.series.count]).frame(width: 9, height: 9)
                        Text(LS(entry.element.label)).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Fmt.percent(Double(entry.element.value) / Double(total))).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

/// Top countries with flag and proportional bar.
struct CountryList: View {
    let items: [ShareItem]
    var limit = 8

    var body: some View {
        let shown = Array(items.prefix(limit))
        let maxValue = max(shown.first?.value ?? 1, 1)
        VStack(spacing: 10) {
            ForEach(shown) { c in
                HStack(spacing: 10) {
                    Text(Fmt.flag(c.id)).font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.label).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text(Fmt.number(c.value)).font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        GeometryReader { geo in
                            Capsule().fill(Theme.accent.opacity(0.85))
                                .frame(width: max(4, geo.size.width * CGFloat(c.value) / CGFloat(maxValue)))
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
    }
}

/// Small sparkline used in rows.
struct MiniSpark: View {
    let values: [Double]
    var tint: Color = Theme.accent

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { entry in
            AreaMark(x: .value("i", entry.offset), y: .value("v", entry.element))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("i", entry.offset), y: .value("v", entry.element))
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

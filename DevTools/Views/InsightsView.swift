import SwiftUI
import Charts

struct InsightsView: View {
    @Environment(DevStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var metric: TrendMetric = .installs

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    struct AppSeriesPoint: Identifiable {
        let id: String
        let date: Date
        let app: String
        let value: Int
    }

    var body: some View {
        let sales = store.sales
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.active?.hasVendor != true {
                    VendorPromptCard()
                } else {
                    if let err = store.salesError { ErrorBanner(message: err) { Task { await store.refreshSales(force: true) } } }

                    LazyVGrid(columns: columns, spacing: 12) {
                        StatTile(title: "Installaties", value: Fmt.number(sales.installs), systemImage: "arrow.down.circle.fill",
                                 footnote: trendText(sales.trend), footnoteColor: sales.trend >= 0 ? Theme.live : Theme.rejected)
                        StatTile(title: "Nieuwe downloads", value: Fmt.number(sales.downloads), systemImage: "sparkles", tint: Theme.cyan)
                        StatTile(title: "Herdownloads", value: Fmt.number(sales.redownloads), systemImage: "arrow.uturn.down.circle", tint: Theme.accent)
                        StatTile(title: "Updates", value: Fmt.number(sales.updates), systemImage: "arrow.triangle.2.circlepath", tint: Theme.pending)
                        StatTile(title: "In-app aankopen", value: Fmt.number(sales.iap), systemImage: "cart.fill", tint: Theme.review)
                        StatTile(title: "Opbrengst", value: Fmt.money(sales.proceeds, sales.currency), systemImage: "eurosign.circle.fill", tint: Theme.live,
                                 footnote: sales.multipleCurrencies ? "omgerekend per valuta, indicatief" : nil)
                    }

                    TrendCard(title: "Portfolio", summary: sales,
                              range: Binding(get: { store.salesRange }, set: { store.setSalesRange($0) }),
                              metric: $metric, loading: store.salesLoading, progress: store.salesProgress)

                    let series = appSeries()
                    if !series.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Installaties per app", subtitle: "Top 5 · \(store.salesRange.title.lowercased())")
                            Chart(series) { p in
                                LineMark(x: .value("Datum", p.date), y: .value("Installaties", p.value))
                                    .foregroundStyle(by: .value("App", p.app))
                                    .interpolationMethod(.monotone)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                            .chartForegroundStyleScale(range: Theme.series)
                            .chartLegend(position: .bottom, alignment: .leading)
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .frame(height: 220)
                        }
                        .devCard()
                    }

                    if sales.perApp.contains(where: { $0.installs > 0 }) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Downloads per app", subtitle: store.salesRange.title)
                            AppDownloadBars(items: sales.perApp, apps: store.apps, limit: 12)
                        }
                        .devCard()
                    }

                    if sales.perApp.contains(where: { $0.proceeds != 0 }) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Opbrengst per app", subtitle: store.salesRange.title)
                            ForEach(sales.perApp.filter { $0.proceeds != 0 }.sorted { $0.proceeds > $1.proceeds }) { a in
                                HStack {
                                    AppIconView(url: store.apps.first { $0.id == a.id }?.iconURL, size: 26, name: a.name)
                                    Text(a.name).font(.subheadline).lineLimit(1)
                                    Spacer()
                                    Text(Fmt.money(a.proceeds, sales.currency)).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.live)
                                }
                            }
                        }
                        .devCard()
                    }

                    let layout = sizeClass == .regular ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))
                    layout {
                        if !sales.countries.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Landen")
                                CountryList(items: sales.countries)
                            }
                            .devCard()
                        }
                        if !sales.devices.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Apparaten")
                                ShareDonut(items: sales.devices)
                            }
                            .devCard()
                        }
                    }
                }

                statusCard
            }
            .padding()
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Insights")
        .refreshable { await store.refreshSales(force: true) }
        .task { await store.refreshSales() }
    }

    private var statusCard: some View {
        let counts = Dictionary(grouping: store.apps, by: { AppState.info(for: $0.headlineState).label }).map { ShareItem(id: $0.key, label: $0.key, value: $0.value.count) }.sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Status van je apps", subtitle: "\(store.apps.count) apps")
            if counts.isEmpty { Text("Geen apps").font(.footnote).foregroundStyle(Theme.textSecondary) }
            else { ShareDonut(items: counts, limit: 6) }
        }
        .devCard()
    }

    private func trendText(_ t: Int) -> String {
        t == 0 ? "stabiel" : (t > 0 ? "▲ \(Fmt.number(t)) t.o.v. eerste helft" : "▼ \(Fmt.number(-t)) t.o.v. eerste helft")
    }

    private func appSeries() -> [AppSeriesPoint] {
        let top = store.sales.perApp.filter { $0.installs > 0 }.prefix(5)
        guard !top.isEmpty else { return [] }
        let ids = Set(top.map(\.id))
        let names = Dictionary(top.map { item in (item.id, store.apps.first(where: { a in a.id == item.id })?.name ?? item.name) }, uniquingKeysWith: { a, _ in a })
        var out: [AppSeriesPoint] = []
        for period in store.salesPeriods {
            var perApp: [String: Int] = [:]
            for row in period.rows where ids.contains(row.appleID) {
                let k = row.kind
                if k == .download || k == .redownload { perApp[row.appleID, default: 0] += row.units }
            }
            for id in ids {
                let name = names[id] ?? id
                out.append(AppSeriesPoint(id: "\(id)-\(period.date.timeIntervalSince1970)", date: period.date, app: name, value: perApp[id] ?? 0))
            }
        }
        return out
    }
}


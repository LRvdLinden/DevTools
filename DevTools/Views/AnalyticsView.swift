import SwiftUI
import Charts

/// App Analytics for one app: impressions, product page views, conversion, sessions, retention, crashes.
struct AnalyticsView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var request: JRes?
    @State private var result = AnalyticsResult()
    @State private var checked = false
    @State private var loading = false
    @State private var progress: Double = 0
    @State private var error: String?
    @State private var days = 30
    @State private var metric: AnalyticsMetric = .impressions
    @State private var enabling = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error { ErrorBanner(message: error) { Task { await load(force: true) } } }
                if !checked {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
                } else if request == nil {
                    enableCard
                } else if result.days.isEmpty && !loading {
                    waitingCard
                } else {
                    Picker("Periode", selection: $days) {
                        Text("7 dagen").tag(7)
                        Text("14 dagen").tag(14)
                        Text("30 dagen").tag(30)
                    }
                    .pickerStyle(.segmented)

                    if loading { ProgressView(value: progress).tint(Theme.accent) }

                    let t = result.total
                    LazyVGrid(columns: columns, spacing: 10) {
                        StatTile(title: "Vertoningen", value: Fmt.number(t.impressions), systemImage: "eye.fill", tint: Theme.accent,
                                 footnote: L("\(Fmt.number(t.uniqueImpressions)) uniek"))
                        StatTile(title: "Productpagina", value: Fmt.number(t.pageViews), systemImage: "doc.richtext.fill", tint: Theme.cyan,
                                 footnote: L("\(Fmt.number(t.uniquePageViews)) unieke bezoekers"))
                        StatTile(title: "Conversie", value: result.conversion.map { String(format: "%.1f%%", $0 * 100) } ?? "—", systemImage: "arrow.down.forward.circle.fill", tint: Theme.live,
                                 footnote: L("\(Fmt.number(t.downloads)) downloads"))
                        StatTile(title: "Eerste downloads", value: Fmt.number(t.firstDownloads), systemImage: "sparkles", tint: Theme.pending,
                                 footnote: L("\(Fmt.number(t.redownloads)) herdownloads"))
                        StatTile(title: "Sessies", value: Fmt.number(t.sessions), systemImage: "play.circle.fill", tint: Theme.live,
                                 footnote: t.sessions > 0 ? L("gem. \(Int(t.sessionSeconds / Double(t.sessions)) / 60) min \(Int(t.sessionSeconds / Double(t.sessions)) % 60) s") : nil)
                        StatTile(title: "Actieve toestellen", value: Fmt.number(t.activeDevices), systemImage: "iphone.gen3", tint: Theme.accent,
                                 footnote: L("som per dag"))
                        StatTile(title: "Retentie dag 1", value: result.retention(day: 1).map(Fmt.percent) ?? "—", systemImage: "arrow.uturn.backward.circle.fill", tint: Theme.cyan,
                                 footnote: result.retention(day: 7).map { L("dag 7: \(Fmt.percent($0))") })
                        StatTile(title: "Crashes", value: Fmt.number(t.crashes), systemImage: "exclamationmark.triangle.fill",
                                 tint: t.crashes > 0 ? Theme.rejected : Theme.textSecondary,
                                 footnote: L("\(Fmt.number(t.deletions)) verwijderingen"))
                    }

                    chartCard

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Over deze cijfers").font(.subheadline.weight(.semibold))
                        Text("Apple levert App Analytics als dagrapporten met 2 tot 5 dagen vertraging. Sessies, installaties en crashes tellen alleen mee als minstens 5 gebruikers hebben ingestemd met het delen van analysegegevens. Apple heeft geen retentierapport: retentie is hier een benadering op basis van sessies van nieuwe gebruikers.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .devCard()
                }
            }
            .padding()
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("App Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(force: false) }
        .refreshable { await load(force: true) }
        .onChange(of: days) { Task { await load(force: false) } }
    }

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("App Analytics inschakelen", systemImage: "chart.bar.doc.horizontal.fill").font(.headline)
            Text("DevTools vraagt Apple eenmalig om doorlopende analyserapporten voor \(app.name). Apple maakt de eerste rapporten binnen 1 à 2 dagen klaar; daarna komen er elke dag nieuwe bij.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
            Text("Hiervoor heeft je API-sleutel de rol Beheerder (Admin) nodig.").font(.caption).foregroundStyle(Theme.textSecondary)
            Button {
                Task { await enable() }
            } label: {
                Label("Inschakelen", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(enabling)
        }
        .devCard()
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Rapporten worden voorbereid", systemImage: "hourglass").font(.headline)
            Text("App Analytics staat aan. Apple maakt de eerste rapporten binnen 1 à 2 dagen klaar. Kom morgen terug of trek omlaag om te verversen.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
            if request?.b("stoppedDueToInactivity") == true {
                Text("Apple heeft de rapporten gestopt omdat ze lang niet zijn opgehaald. Schakel opnieuw in.").font(.footnote).foregroundStyle(Theme.review)
                Button("Opnieuw inschakelen") { Task { await enable() } }.disabled(enabling)
            }
        }
        .devCard()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Grafiek", selection: $metric) {
                ForEach(AnalyticsMetric.allCases) { m in Text(LS(m.title)).tag(m) }
            }
            .pickerStyle(.menu)
            Chart(result.days, id: \.date) { d in
                let date = AnalyticsEngine.dayFormatter.date(from: d.date) ?? .now
                AreaMark(x: .value("Dag", date, unit: .day), y: .value(LS(metric.title), metric.value(d)))
                    .foregroundStyle(LinearGradient(colors: [metric.color.opacity(0.35), metric.color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Dag", date, unit: .day), y: .value(LS(metric.title), metric.value(d)))
                    .foregroundStyle(metric.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .frame(height: 200)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        }
        .devCard()
    }

    private func load(force: Bool) async {
        guard let api = store.api else { return }
        do {
            if !checked || force { request = try await AnalyticsEngine.ongoingRequest(api: api, appID: app.id) }
            checked = true
            if store.isDemo && request == nil { request = JRes(["id": "demo", "type": "analyticsReportRequests"]) }
            guard let request else { return }
            loading = true
            defer { loading = false }
            progress = 0
            result = try await AnalyticsEngine.load(api: api, appID: app.id, requestID: request.id, days: days) { p in progress = p }
            error = nil
        } catch {
            checked = true
            self.error = error.localizedDescription
        }
    }

    private func enable() async {
        guard let api = store.api else { return }
        enabling = true
        defer { enabling = false }
        do { try await AnalyticsEngine.enable(api: api, appID: app.id); await load(force: true) }
        catch { self.error = error.localizedDescription }
    }
}

enum AnalyticsMetric: String, CaseIterable, Identifiable {
    case impressions, pageViews, downloads, sessions, activeDevices, crashes, deletions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .impressions: return "Vertoningen"
        case .pageViews: return "Productpagina"
        case .downloads: return "Downloads"
        case .sessions: return "Sessies"
        case .activeDevices: return "Actieve toestellen"
        case .crashes: return "Crashes"
        case .deletions: return "Verwijderingen"
        }
    }
    var color: Color {
        switch self {
        case .impressions, .activeDevices: return Theme.accent
        case .pageViews: return Theme.cyan
        case .downloads: return Theme.pending
        case .sessions: return Theme.live
        case .crashes, .deletions: return Theme.rejected
        }
    }
    func value(_ d: AnalyticsDay) -> Int {
        switch self {
        case .impressions: return d.impressions
        case .pageViews: return d.pageViews
        case .downloads: return d.downloads
        case .sessions: return d.sessions
        case .activeDevices: return d.activeDevices
        case .crashes: return d.crashes
        case .deletions: return d.deletions
        }
    }
}

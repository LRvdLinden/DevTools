import SwiftUI

// MARK: - In-app events, custom product pages, product page experiments, Game Center

struct ExtrasView: View {
    let app: AppSummary
    var body: some View {
        List {
            Section {
                NavigationLink { AppEventsView(app: app) } label: { InfoRow(title: L("In-app events"), subtitle: L("Evenementen op je productpagina en in zoekresultaten"), icon: "calendar.badge.clock", tint: Theme.pending) }
                NavigationLink { CustomPagesView(app: app) } label: { InfoRow(title: L("Custom product pages"), subtitle: L("Extra productpagina's met eigen screenshots en link"), icon: "rectangle.stack.fill", tint: Theme.accent) }
                NavigationLink { ExperimentsView(app: app) } label: { InfoRow(title: L("A/B-tests van je productpagina"), subtitle: L("Product page optimization"), icon: "flask.fill", tint: Theme.cyan) }
                NavigationLink { GameCenterView(app: app) } label: { InfoRow(title: L("Game Center"), subtitle: L("Prestaties en ranglijsten"), icon: "gamecontroller.fill", tint: Theme.live) }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Meer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppEventsView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var loader = Loader()

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            ForEach(loader.doc.data) { ev in
                let schedule = (ev.list("territorySchedules").first as? [String: Any]) ?? [:]
                let start = ASCDate.parse(schedule["eventStart"] as? String), end = ASCDate.parse(schedule["eventEnd"] as? String)
                InfoRow(title: ev.str("referenceName"),
                        subtitle: [Pretty.label(ev.s("badge")), start.map { "\(Fmt.day($0)) – \(Fmt.day(end))" }, ev.s("priority").map { L("prioriteit \(Pretty.label($0))") }]
                            .compactMap { $0 }.joined(separator: " · "),
                        icon: "calendar", tint: Theme.pending, badge: ev.s("eventState"))
            }
            .cardRows()
        }
        .themedList()
        .overlay { ListStatus(loader: loader, empty: "Geen in-app events") }
        .navigationTitle("In-app events")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/apps/\(app.id)/appEvents", [("limit", "50")], all: true) }
    }
}

struct CustomPagesView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var loader = Loader()
    @State private var feedback: String?

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            ForEach(loader.doc.data) { p in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(get: { p.b("visible") ?? false }, set: { v in Task { await setVisible(p, v) } })) {
                        InfoRow(title: p.str("name"), subtitle: p.s("url"), icon: "rectangle.stack.fill", tint: Theme.accent)
                    }
                    if let u = p.s("url"), let url = URL(string: u) {
                        HStack {
                            Button { UIPasteboard.general.string = u; feedback = L("Link gekopieerd") } label: { Label("Kopieer link", systemImage: "link") }
                            Spacer()
                            Button { openURL(url) } label: { Label("Open", systemImage: "safari") }
                        }
                        .font(.caption).buttonStyle(.borderless)
                    }
                }
            }
            .cardRows()
        }
        .themedList()
        .overlay { ListStatus(loader: loader, empty: "Geen custom product pages") }
        .navigationTitle("Custom product pages")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/apps/\(app.id)/appCustomProductPages", [("limit", "50")], all: true) }
    }

    private func setVisible(_ p: JRes, _ v: Bool) async {
        guard let api = store.api else { return }
        do { try await api.jpatch("/v1/appCustomProductPages/\(p.id)", type: "appCustomProductPages", id: p.id, attributes: ["visible": v]); await load() }
        catch { loader.error = error.localizedDescription }
    }
}

struct ExperimentsView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var loader = Loader()

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            ForEach(loader.doc.data) { x in
                NavigationLink { ExperimentDetailView(experiment: x) } label: {
                    InfoRow(title: x.str("name"),
                            subtitle: [x.i("trafficProportion").map { L("\($0)% van het verkeer") },
                                       x.date("startDate").map { L("gestart \(Fmt.day($0))") },
                                       x.date("endDate").map { L("tot \(Fmt.day($0))") }].compactMap { $0 }.joined(separator: " · "),
                            icon: "flask.fill", tint: Theme.cyan, badge: x.s("state"))
                }
            }
            .cardRows()
        }
        .themedList()
        .overlay { ListStatus(loader: loader, empty: "Geen A/B-tests") }
        .navigationTitle("A/B-tests")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/apps/\(app.id)/appStoreVersionExperimentsV2", [("limit", "50")], all: true) }
    }
}

struct ExperimentDetailView: View {
    let experiment: JRes
    @Environment(DevStore.self) private var store
    @State private var loader = Loader()

    var body: some View {
        List {
            Section {
                LabeledContent("Status") { StateBadge(state: experiment.str("state")) }
                if let t = experiment.i("trafficProportion") { LabeledContent("Verkeer", value: "\(t)%") }
                if let s = experiment.date("startDate") { LabeledContent("Start", value: Fmt.day(s)) }
                if let e = experiment.date("endDate") { LabeledContent("Einde", value: Fmt.day(e)) }
                if let p = experiment.s("platform") { LabeledContent("Platform", value: Platform.label(p)) }
            }
            .cardRows()
            Section("Varianten") {
                ForEach(loader.doc.data) { t in
                    InfoRow(title: t.str("name"), subtitle: t.date("promotedDate").map { L("gepromoveerd \(Fmt.day($0))") } ?? t.s("appIconName"),
                            icon: "square.on.square", tint: Theme.accent)
                }
                if loader.doc.data.isEmpty && loader.loaded { Text("Geen varianten").font(.footnote).foregroundStyle(Theme.textSecondary) }
            }
            .cardRows()
            Section {
                Text("Resultaten van A/B-tests (conversie per variant) toont Apple alleen in App Store Connect.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(experiment.str("name"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let api = store.api else { return }
            await loader.run { try await api.jget("/v2/appStoreVersionExperiments/\(experiment.id)/appStoreVersionExperimentTreatments", [("limit", "20")]) }
        }
    }
}

struct GameCenterView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var detail: JRes?
    @State private var achievements: [JRes] = []
    @State private var leaderboards: [JRes] = []
    @State private var loading = true
    @State private var error: String?
    @State private var none = false

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if none {
                ContentUnavailableView("Game Center staat uit", systemImage: "gamecontroller", description: Text("Deze app gebruikt geen Game Center."))
                    .listRowBackground(Color.clear)
            }
            if detail != nil {
                Section("Ranglijsten (\(leaderboards.count))") {
                    ForEach(leaderboards) { l in
                        InfoRow(title: l.str("referenceName"),
                                subtitle: [l.s("vendorIdentifier"), l.s("submissionType").map(Pretty.label), l.s("scoreSortType").map { $0 == "DESC" ? L("hoogste eerst") : L("laagste eerst") }]
                                    .compactMap { $0 }.joined(separator: " · "),
                                icon: "list.number", tint: Theme.accent, badge: l.b("archived") == true ? "ARCHIVED" : nil)
                    }
                }
                .cardRows()
                Section("Prestaties (\(achievements.count))") {
                    ForEach(achievements) { a in
                        InfoRow(title: a.str("referenceName"),
                                subtitle: [a.s("vendorIdentifier"), a.i("points").map { L("\($0) punten") }, a.b("repeatable") == true ? L("herhaalbaar") : nil]
                                    .compactMap { $0 }.joined(separator: " · "),
                                icon: "trophy.fill", tint: .yellow, badge: a.b("archived") == true ? "ARCHIVED" : nil)
                    }
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay { if loading && detail == nil && !none { ProgressView() } }
        .navigationTitle("Game Center")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do {
            guard let d = try await api.jget("/v1/apps/\(app.id)/gameCenterDetail").data.first else { none = true; return }
            detail = d
            achievements = (try? await api.jget("/v1/gameCenterDetails/\(d.id)/gameCenterAchievements", [("limit", "200")], all: true).data) ?? []
            leaderboards = (try? await api.jget("/v1/gameCenterDetails/\(d.id)/gameCenterLeaderboards", [("limit", "200")], all: true).data) ?? []
            error = nil
        } catch let e as ConnectError where e.status == 404 {
            none = true
        } catch { self.error = error.localizedDescription }
    }
}

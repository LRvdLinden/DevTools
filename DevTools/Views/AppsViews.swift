import SwiftUI
import Charts

struct AppsListView: View {
    @Environment(DevStore.self) private var store
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var sort: Sort = .name

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Alle", live = "Live", review = "In review", preparing = "In voorbereiding", rejected = "Afgewezen"
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case name = "Naam", downloads = "Downloads", updated = "Laatste build"
        var id: String { rawValue }
    }

    private var shown: [AppSummary] {
        var list = store.apps.filter { app in
            query.isEmpty || app.name.localizedCaseInsensitiveContains(query) || app.bundleID.localizedCaseInsensitiveContains(query)
        }
        switch filter {
        case .all: break
        case .live: list = list.filter(\.isLive)
        case .review: list = list.filter(\.inReview)
        case .preparing: list = list.filter { $0.pendingVersion?.state == "PREPARE_FOR_SUBMISSION" }
        case .rejected: list = list.filter(\.isRejected)
        }
        switch sort {
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .downloads: list.sort { (store.appSales($0.id)?.installs ?? 0) > (store.appSales($1.id)?.installs ?? 0) }
        case .updated: list.sort { ($0.latestBuild?.uploaded ?? .distantPast) > ($1.latestBuild?.uploaded ?? .distantPast) }
        }
        return list
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { f in
                            Button { withAnimation(.snappy) { filter = f } } label: {
                                Text(LS(f.rawValue))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(filter == f ? Theme.accent : Theme.card, in: Capsule())
                                    .foregroundStyle(filter == f ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            Section {
                ForEach(shown) { app in
                    NavigationLink { AppDetailView(appID: app.id) } label: {
                        AppRow(app: app, downloads: store.active?.hasVendor == true ? store.appSales(app.id)?.installs ?? 0 : nil)
                    }
                }
            } footer: {
                Text("\(shown.count) van \(store.apps.count) apps").font(.caption)
            }
            .cardRows()
        }
        .themedList()
        .overlay {
            if store.apps.isEmpty && store.loading { ProgressView("Apps laden…") }
            else if shown.isEmpty && !store.apps.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "Zoek app of bundle ID")
        .navigationTitle("Apps")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sorteren", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down.circle") }
            }
        }
        .refreshable { await store.refresh() }
    }
}

struct AppDetailView: View {
    let appID: String
    @Environment(DevStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var builds: [BuildInfo] = []
    @State private var buildsError: String?
    @State private var metric: TrendMetric = .installs
    @State private var showNewVersion = false
    @State private var newVersion: VersionInfo?
    @State private var feedback: String?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 10)]

    var body: some View {
        if let app = store.apps.first(where: { $0.id == appID }) {
            content(app)
        } else {
            ContentUnavailableView("App niet gevonden", systemImage: "app.dashed")
        }
    }

    private func content(_ app: AppSummary) -> some View {
        let summary = SalesSummary(periods: store.salesPeriods, apps: store.apps, appID: app.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(app)

                LazyVGrid(columns: columns, spacing: 10) {
                    if store.active?.hasVendor == true {
                        StatTile(title: "Installaties", value: Fmt.number(summary.installs), systemImage: "arrow.down.circle.fill", footnote: store.salesRange.title)
                        StatTile(title: "Opbrengst", value: Fmt.money(summary.proceeds, summary.currency.isEmpty ? store.sales.currency : summary.currency), systemImage: "eurosign.circle.fill", tint: Theme.live)
                        StatTile(title: "Updates", value: Fmt.number(summary.updates), systemImage: "arrow.triangle.2.circlepath", tint: Theme.pending)
                    }
                    StatTile(title: "Rating", value: app.rating.map { String(format: "%.1f ★", $0) } ?? "—", systemImage: "star.fill", tint: .yellow,
                             footnote: app.ratingCount.map { L("\(Fmt.number($0)) beoordelingen") })
                    StatTile(title: "Laatste build", value: app.latestBuild?.number ?? "—", systemImage: "hammer.fill", tint: Theme.cyan,
                             footnote: app.latestBuild.map { Fmt.relative($0.uploaded) })
                }

                if store.active?.hasVendor == true {
                    TrendCard(title: "Downloads", summary: summary,
                              range: Binding(get: { store.salesRange }, set: { store.setSalesRange($0) }),
                              metric: $metric, loading: store.salesLoading, progress: store.salesProgress)
                    if !summary.countries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Top landen", subtitle: store.salesRange.title)
                            CountryList(items: summary.countries, limit: 6)
                        }
                        .devCard()
                    }
                }

                versionsCard(app)
                buildsCard(app)
                manageCard(app)
            }
            .padding()
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showNewVersion = true } label: { Label("Nieuwe versie", systemImage: "plus.square.on.square") }
                    if let url = app.publicStoreURL, app.isLive { Button { openURL(url) } label: { Label("Bekijk in App Store", systemImage: "bag") } }
                    if let url = app.appStoreConnectURL { Button { openURL(url) } label: { Label("Open in App Store Connect", systemImage: "safari") } }
                    Button { UIPasteboard.general.string = app.bundleID; feedback = "Bundle ID gekopieerd" } label: { Label("Kopieer bundle ID", systemImage: "doc.on.doc") }
                    Button { UIPasteboard.general.string = app.id; feedback = "Apple ID gekopieerd" } label: { Label("Kopieer Apple ID", systemImage: "number") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .refreshable {
            await store.reloadApp(app.id)
            await loadBuilds()
        }
        .task(id: app.id) { await loadBuilds() }
        .sheet(isPresented: $showNewVersion) {
            CreateVersionSheet(app: app) { created in newVersion = created }
        }
        .navigationDestination(item: $newVersion) { v in VersionDetailView(appID: app.id, version: v) }
        .actionFeedback($feedback)
    }

    private func header(_ app: AppSummary) -> some View {
        HStack(alignment: .center, spacing: 16) {
            AppIconView(url: app.iconURL, size: 88, name: app.name)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(app.name).font(.title2.weight(.bold)).lineLimit(2)
                Text(app.bundleID).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary).textSelection(.enabled).lineLimit(1)
                HStack(spacing: 6) {
                    if let live = app.liveVersion { pill("Live \(live.versionString)", Theme.live) }
                    if let p = app.pendingVersion { StateBadge(state: p.state) }
                }
                HStack(spacing: 6) {
                    ForEach(app.platforms, id: \.self) { p in
                        Label(Platform.label(p), systemImage: Platform.icon(p))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .devCard()
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(LS(text))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func versionsCard(_ app: AppSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "App Store-versies", systemImage: "app.badge")
                Button { showNewVersion = true } label: { Label("Nieuw", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            if app.versions.isEmpty {
                Text("Nog geen versies").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(app.versions.prefix(6)) { v in
                NavigationLink { VersionDetailView(appID: app.id, version: v) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: Platform.icon(v.platform)).foregroundStyle(Theme.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(v.platformLabel) \(v.versionString)").font(.subheadline.weight(.semibold))
                            Text(v.created.map { L("Aangemaakt \(Fmt.day($0))") } ?? "").font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        StateBadge(state: v.state)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if v.id != app.versions.prefix(6).last?.id { Divider() }
            }
        }
        .devCard()
    }

    private func buildsCard(_ app: AppSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "TestFlight-builds", systemImage: "airplane")
                NavigationLink("Alles") { AppBuildsView(app: app) }.font(.subheadline.weight(.medium))
            }
            if let buildsError { Text(buildsError).font(.caption).foregroundStyle(Theme.rejected) }
            if builds.isEmpty && buildsError == nil {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 8)
            }
            ForEach(builds.prefix(5)) { b in
                NavigationLink { BuildDetailView(app: app, buildID: b.id) } label: {
                    BuildRow(build: b).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if b.id != builds.prefix(5).last?.id { Divider() }
            }
        }
        .devCard()
    }

    private func manageCard(_ app: AppSummary) -> some View {
        VStack(spacing: 0) {
            manageRow("Beoordelingen & reacties", "star.bubble.fill", .yellow) { ReviewsView(app: app) }
            Divider().padding(.leading, 44)
            manageRow("App-informatie (naam, ondertitel)", "textformat", Theme.accent) { AppInfoEditorView(app: app) }
            Divider().padding(.leading, 44)
            manageRow("Testgroepen & testers", "person.3.fill", Theme.cyan) { BetaGroupsView(app: app) }
        }
        .devCard(padding: 6)
    }

    private func manageRow<D: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(LS(title)).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadBuilds() async {
        guard let api = store.api else { return }
        do {
            builds = try await api.builds(appID: appID, limit: 5)
            buildsError = builds.isEmpty ? "Nog geen builds geüpload" : nil
        } catch {
            buildsError = error.localizedDescription
        }
    }
}

struct BuildRow: View {
    let build: BuildInfo

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let url = build.iconURL {
                    AppIconView(url: url, size: 38)
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardRaised).frame(width: 38, height: 38)
                    Image(systemName: "hammer.fill").foregroundStyle(Theme.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(build.title).font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(Platform.label(build.platform)).font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 6) {
                    Text(Fmt.relative(build.uploaded))
                    if let exp = build.expires, !build.expired {
                        let days = Calendar.current.dateComponents([.day], from: .now, to: exp).day ?? 0
                        Text("· verloopt over \(max(days, 0)) d").foregroundStyle(days < 10 ? Theme.review : Theme.textSecondary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            StateBadge(state: build.displayState)
        }
    }
}

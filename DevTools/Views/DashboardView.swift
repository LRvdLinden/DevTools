import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(DevStore.self) private var store
    @State private var metric: TrendMetric = .installs

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        let apps = store.apps
        let sales = store.sales
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let err = store.error {
                    ErrorBanner(message: err) { Task { await store.refresh() } }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    if store.active?.hasVendor == true {
                        StatTile(title: "Installaties", value: sales.points.isEmpty ? "…" : Fmt.number(sales.installs),
                                 systemImage: "arrow.down.circle.fill", tint: Theme.accent,
                                 footnote: store.salesRange.title)
                        StatTile(title: "Opbrengst", value: sales.points.isEmpty ? "…" : Fmt.money(sales.proceeds, sales.currency),
                                 systemImage: "eurosign.circle.fill", tint: Theme.live,
                                 footnote: sales.iap > 0 ? "\(Fmt.number(sales.iap)) in-app aankopen" : nil)
                    }
                    StatTile(title: "Live", value: "\(apps.filter(\.isLive).count)", systemImage: "checkmark.seal.fill", tint: Theme.live,
                             footnote: "van \(apps.count) apps")
                    StatTile(title: "In review", value: "\(apps.filter(\.inReview).count)", systemImage: "hourglass",
                             tint: apps.contains(where: \.inReview) ? Theme.review : Theme.textSecondary)
                    if store.active?.hasVendor == true {
                        StatTile(title: "Updates", value: sales.points.isEmpty ? "…" : Fmt.number(sales.updates), systemImage: "arrow.triangle.2.circlepath", tint: Theme.pending)
                    }
                    StatTile(title: "Gem. rating", value: averageRating(apps), systemImage: "star.fill", tint: .yellow)
                }

                if store.active?.hasVendor != true {
                    VendorPromptCard()
                } else {
                    if let err = store.salesError { ErrorBanner(message: err) { Task { await store.refreshSales(force: true) } } }
                    TrendCard(title: "Downloads & opbrengst", summary: sales,
                              range: Binding(get: { store.salesRange }, set: { store.setSalesRange($0) }),
                              metric: $metric, loading: store.salesLoading, progress: store.salesProgress)
                    if sales.perApp.contains(where: { $0.installs > 0 }) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Downloads per app", subtitle: store.salesRange.title)
                            AppDownloadBars(items: sales.perApp, apps: apps)
                        }
                        .devCard()
                    }
                }

                ActionNeededCard(apps: apps)

                if !apps.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Mijn apps").font(.headline)
                            Spacer()
                            NavigationLink("Alles") { AppsListView() }.font(.subheadline.weight(.medium))
                        }
                        .padding([.horizontal, .top])
                        .padding(.bottom, 6)
                        ForEach(apps.prefix(8)) { app in
                            NavigationLink { AppDetailView(appID: app.id) } label: {
                                AppRow(app: app, downloads: store.appSales(app.id)?.installs)
                                    .padding(.horizontal).padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            if app.id != apps.prefix(8).last?.id { Divider().padding(.leading, 72) }
                        }
                        .padding(.bottom, 6)
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if store.loading {
                    ProgressView("Apps laden…").frame(maxWidth: .infinity).padding(.top, 40)
                } else if store.error == nil {
                    ContentUnavailableView("Nog geen apps", systemImage: "app.dashed", description: Text("Deze API-sleutel heeft geen toegang tot apps."))
                }
            }
            .padding()
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { AccountSwitcherMenu() }
        }
        .refreshable {
            await store.refresh()
            await store.refreshSales(force: true)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("SplashLogo").resizable().scaledToFit().frame(width: 46, height: 46)
                .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.title3.weight(.semibold))
                if let last = store.lastRefresh {
                    Text("\(store.active?.name ?? "") · bijgewerkt \(Fmt.relative(last))").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                } else {
                    Text(store.active?.name ?? "").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if store.loading || store.salesLoading { ProgressView() }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 5..<12: return "Goedemorgen"
        case 12..<18: return "Goedemiddag"
        default: return "Goedenavond"
        }
    }

    private func averageRating(_ apps: [AppSummary]) -> String {
        let rated = apps.compactMap { app -> (Double, Int)? in
            guard let r = app.rating, let c = app.ratingCount, c > 0 else { return nil }
            return (r, c)
        }
        let count = rated.reduce(0) { $0 + $1.1 }
        guard count > 0 else { return "—" }
        let avg = rated.reduce(0.0) { $0 + $1.0 * Double($1.1) } / Double(count)
        return String(format: "%.1f ★", avg)
    }
}

struct VendorPromptCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Downloads en opbrengst activeren", systemImage: "chart.bar.xaxis").font(.headline)
            Text("Vul je vendornummer in bij je account om downloads, updates, in-app aankopen en opbrengst per app te zien. Je vindt het in App Store Connect onder Business, naast je adres. De API-sleutel heeft de rol Admin, Finance of Sales nodig.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            NavigationLink { AccountView() } label: {
                Label("Naar account", systemImage: "arrow.right.circle.fill").font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Apps that need attention: rejected, in review, waiting for release, missing compliance.
struct ActionNeededCard: View {
    let apps: [AppSummary]

    var body: some View {
        let items = entries
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Aandacht nodig", systemImage: "bell.badge.fill").font(.headline).foregroundStyle(Theme.review)
                ForEach(Array(items.enumerated()), id: \.offset) { pair in
                    let entry = pair.element
                    NavigationLink { AppDetailView(appID: entry.0.id) } label: {
                        HStack(spacing: 10) {
                            AppIconView(url: entry.0.iconURL, size: 30, name: entry.0.name)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.0.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(entry.1).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            StateBadge(state: entry.2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Theme.review.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var entries: [(AppSummary, String, String)] {
        var out: [(AppSummary, String, String)] = []
        for app in apps {
            if let p = app.pendingVersion {
                switch p.state {
                case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY":
                    out.append((app, "Versie \(p.versionString) is afgewezen", p.state))
                case "WAITING_FOR_REVIEW", "IN_REVIEW":
                    out.append((app, "Versie \(p.versionString) bij App Review", p.state))
                case "PENDING_DEVELOPER_RELEASE":
                    out.append((app, "Versie \(p.versionString) kan vrijgegeven worden", p.state))
                default: break
                }
            }
            if let b = app.latestBuild, b.needsCompliance {
                out.append((app, "Build \(b.number): export compliance ontbreekt", "MISSING_EXPORT_COMPLIANCE"))
            }
        }
        return out
    }
}

struct AppRow: View {
    let app: AppSummary
    var downloads: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(url: app.iconURL, size: 46, name: app.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    if let live = app.liveVersion {
                        Text("Live \(live.versionString)").foregroundStyle(Theme.live)
                    }
                    if let p = app.pendingVersion {
                        Text("\(AppState.info(for: p.state).label) \(p.versionString)").foregroundStyle(AppState.info(for: p.state).color)
                    }
                    if app.liveVersion == nil && app.pendingVersion == nil { Text("Nog niet uitgebracht").foregroundStyle(Theme.textSecondary) }
                }
                .font(.caption.weight(.medium))
                .lineLimit(1)
                HStack(spacing: 8) {
                    if let b = app.latestBuild { Label("Build \(b.number)", systemImage: "hammer").foregroundStyle(Theme.textSecondary) }
                    if let r = app.rating, (app.ratingCount ?? 0) > 0 { Label(String(format: "%.1f", r), systemImage: "star.fill").foregroundStyle(.yellow) }
                }
                .font(.caption2)
                .labelStyle(CompactLabelStyle())
            }
            Spacer(minLength: 4)
            if let downloads {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.compact(downloads)).font(.headline.monospacedDigit())
                    Text("downloads").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            } else {
                StateBadge(state: app.headlineState, compact: true)
            }
        }
        .contentShape(Rectangle())
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

struct AccountSwitcherMenu: View {
    @Environment(DevStore.self) private var store

    var body: some View {
        Menu {
            ForEach(store.accounts) { account in
                Button {
                    store.select(account)
                } label: {
                    if account.id == store.selectedID { Label(account.name, systemImage: "checkmark") } else { Text(account.name) }
                }
            }
            Divider()
            Button { Task { await store.refresh() } } label: { Label("Verversen", systemImage: "arrow.clockwise") }
        } label: {
            Image(systemName: store.loading ? "arrow.triangle.2.circlepath" : "person.crop.circle")
                .symbolEffect(.pulse, isActive: store.loading)
        }
    }
}

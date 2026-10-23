import Foundation
import SwiftUI
import WidgetKit
import UIKit

/// Central state: accounts, apps with versions/builds/icons, and sales.
@MainActor
@Observable
final class DevStore {
    var accounts: [DeveloperAccount] = []
    var selectedID: UUID?
    var apps: [AppSummary] = []
    var loading = false
    var error: String?
    var lastRefresh: Date?

    /// Shown on the splash screen while the first load runs.
    var phase = "Opstarten…"
    var progress: Double = 0

    // Sales (portfolio)
    var salesRange: SalesRange = .month
    var sales = SalesSummary()
    var salesPeriods: [SalesPeriod] = []
    var salesLoading = false
    var salesError: String?
    var salesProgress: Double = 0
    var salesUpdated: Date?

    @ObservationIgnored private var generation = 0

    init() {
        if let data = UserDefaults.standard.data(forKey: "accounts"),
           let saved = try? JSONDecoder().decode([DeveloperAccount].self, from: data) { accounts = saved }
        if let raw = UserDefaults.standard.string(forKey: "selectedAccount") { selectedID = UUID(uuidString: raw) }
        if selectedID == nil || !accounts.contains(where: { $0.id == selectedID }) { selectedID = accounts.first?.id }
        if let r = UserDefaults.standard.string(forKey: "salesRange"), let range = SalesRange(rawValue: r) { salesRange = range }
        loadCachedApps()
    }

    var active: DeveloperAccount? { accounts.first { $0.id == selectedID } }
    var api: ConnectAPI? { active.map { ConnectAPI(account: $0) } }

    func requireAPI() throws -> ConnectAPI {
        guard let api else { throw ConnectError(message: "Geen account geselecteerd") }
        return api
    }

    // MARK: Accounts

    func add(name: String, issuer: String, key: String, pem: String, vendor: String) throws {
        let item = DeveloperAccount(name: name,
                                    issuerID: issuer.trimmingCharacters(in: .whitespacesAndNewlines),
                                    keyID: key.trimmingCharacters(in: .whitespacesAndNewlines),
                                    vendorNumber: vendor.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !item.issuerID.isEmpty, !item.keyID.isEmpty, pem.contains("PRIVATE KEY") else {
            throw ConnectError(message: "Vul Issuer ID en Key ID in en kies een geldig .p8-bestand")
        }
        try Vault.save(pem, key: item.id.uuidString)
        accounts.append(item)
        selectedID = item.id
        apps = []
        persist()
    }

    func update(_ account: DeveloperAccount) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let vendorChanged = accounts[i].vendorNumber != account.vendorNumber
        accounts[i] = account
        persist()
        if vendorChanged && account.id == selectedID { Task { await refreshSales(force: true) } }
    }

    func remove(_ account: DeveloperAccount) {
        Vault.delete(account.id.uuidString)
        accounts.removeAll { $0.id == account.id }
        if selectedID == account.id {
            selectedID = accounts.first?.id
            resetData()
            if active != nil { Task { await refresh() } }
        }
        persist()
    }

    func select(_ account: DeveloperAccount) {
        guard account.id != selectedID else { return }
        selectedID = account.id
        resetData()
        persist()
        loadCachedApps()
        Task { await refresh() }
    }

    private func resetData() {
        generation += 1
        apps = []
        sales = SalesSummary()
        salesPeriods = []
        salesError = nil
        error = nil
        lastRefresh = nil
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: "accounts")
        UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedAccount")
    }

    // MARK: Local cache (instant start)

    private var appsCacheURL: URL? {
        guard let id = selectedID else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("apps-\(id.uuidString).json")
    }

    private func loadCachedApps() {
        guard let url = appsCacheURL, let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode([AppSummary].self, from: data) else { return }
        apps = cached
    }

    private func saveCachedApps() {
        guard let url = appsCacheURL, let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: url)
    }

    // MARK: Refresh

    func refresh() async {
        guard let account = active, !loading else { return }
        let gen = generation
        let api = ConnectAPI(account: account)
        loading = true
        error = nil
        defer { if gen == generation { loading = false } }
        phase = "Verbinden met App Store Connect…"
        progress = 0.1
        do {
            let result: (data: [Resource<AppAttributes>], included: [AnyResource]) = try await api.all("/v1/apps", [
                ("limit", "200"),
                ("fields[apps]", "name,bundleId,sku,primaryLocale")
            ], max: 400)
            let items = result.data
            guard gen == generation else { return }
            phase = "Versies en builds ophalen…"
            progress = 0.3
            var fresh: [AppSummary] = items.map { r in
                var a = AppSummary(id: r.id, name: r.attributes.name ?? "App", bundleID: r.attributes.bundleId ?? "",
                                   sku: r.attributes.sku ?? "", primaryLocale: r.attributes.primaryLocale ?? "en-US")
                if let old = apps.first(where: { $0.id == r.id }) {
                    a.versions = old.versions; a.latestBuild = old.latestBuild
                    a.artworkURL = old.artworkURL; a.rating = old.rating; a.ratingCount = old.ratingCount; a.storeURL = old.storeURL
                }
                return a
            }

            let ids = fresh.map(\.id)
            var done = 0
            var index = 0
            while index < ids.count {
                let chunk = Array(ids[index..<min(index + 6, ids.count)])
                index += 6
                await withTaskGroup(of: (String, [VersionInfo]?, BuildInfo?).self) { group in
                    for id in chunk {
                        group.addTask { await Self.loadDetails(api: api, appID: id) }
                    }
                    for await (id, versions, build) in group {
                        done += 1
                        if let i = fresh.firstIndex(where: { $0.id == id }) {
                            if let versions { fresh[i].versions = versions }
                            if let build { fresh[i].latestBuild = build }
                        }
                    }
                }
                progress = 0.3 + 0.45 * Double(done) / Double(max(ids.count, 1))
            }

            phase = "App-iconen en beoordelingen…"
            progress = 0.8
            let lookup = await StoreLookup.fetch(ids: ids)
            for i in fresh.indices {
                if let info = lookup[fresh[i].id] {
                    fresh[i].artworkURL = info.artwork
                    fresh[i].rating = info.rating
                    fresh[i].ratingCount = info.ratingCount
                    fresh[i].storeURL = info.url
                }
            }
            guard gen == generation else { return }
            apps = fresh.sorted { a, b in
                if a.isLive != b.isLive { return a.isLive }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            lastRefresh = .now
            progress = 1
            phase = "Klaar"
            saveCachedApps()
            publishSnapshot()
        } catch {
            guard gen == generation else { return }
            self.error = error.localizedDescription
            progress = 1
        }
        Task { await refreshSales() }
    }

    nonisolated private static func loadDetails(api: ConnectAPI, appID: String) async -> (String, [VersionInfo]?, BuildInfo?) {
        async let versionsDoc: ListDocument<VersionAttributes> = api.get("/v1/apps/\(appID)/appStoreVersions", [
            ("limit", "12")
        ])
        async let buildsDoc: ListDocument<BuildAttributes> = api.get("/v1/builds", [
            ("filter[app]", appID),
            ("sort", "-uploadedDate"),
            ("limit", "1"),
            ("include", "preReleaseVersion,buildBetaDetail")
        ])
        let v = try? await versionsDoc
        let b = try? await buildsDoc
        let versions = v.map { doc in
            doc.data.map { VersionInfo($0) }.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        }
        let build = b.flatMap { doc in doc.data.first.map { BuildInfo($0, included: doc.included ?? []) } }
        return (appID, versions, build)
    }

    func replace(_ app: AppSummary) {
        if let i = apps.firstIndex(where: { $0.id == app.id }) { apps[i] = app }
    }

    /// Reloads the versions/latest build of a single app after an edit.
    func reloadApp(_ id: String) async {
        guard let api else { return }
        let (_, versions, build) = await Self.loadDetails(api: api, appID: id)
        if let i = apps.firstIndex(where: { $0.id == id }) {
            if let versions { apps[i].versions = versions }
            if let build { apps[i].latestBuild = build }
            saveCachedApps()
            publishSnapshot()
        }
    }

    // MARK: Sales

    func setSalesRange(_ range: SalesRange) {
        salesRange = range
        UserDefaults.standard.set(range.rawValue, forKey: "salesRange")
        Task { await refreshSales(force: true) }
    }

    func refreshSales(force: Bool = false) async {
        guard let account = active else { return }
        guard account.hasVendor else {
            sales = SalesSummary(); salesPeriods = []; salesError = nil
            return
        }
        if salesLoading { return }
        if !force, let salesUpdated, Date().timeIntervalSince(salesUpdated) < 300, !salesPeriods.isEmpty { return }
        let gen = generation
        let range = salesRange
        salesLoading = true
        salesProgress = 0
        defer { if gen == generation { salesLoading = false } }
        let result = await SalesEngine.load(account: account, range: range) { [weak self] p in self?.salesProgress = p }
        guard gen == generation, range == salesRange else { return }
        salesPeriods = result.periods
        salesError = result.error
        sales = SalesSummary(periods: result.periods, apps: apps)
        salesUpdated = .now
        publishSnapshot()
    }

    func appSales(_ id: String) -> AppSales? { sales.perApp.first { $0.id == id } }

    // MARK: Widgets + Watch

    func publishSnapshot() {
        let byApp = Dictionary(sales.perApp.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let hasSales = !sales.points.isEmpty
        // Daily installs per app from the loaded report periods.
        var perAppHistory: [String: [HistoryPoint]] = [:]
        for period in salesPeriods {
            var day: [String: Int] = [:]
            for row in period.rows where row.kind == .download || row.kind == .redownload {
                day[row.appleID, default: 0] += row.units
            }
            for app in apps {
                perAppHistory[app.id, default: []].append(HistoryPoint(date: period.date, value: day[app.id] ?? 0))
            }
        }
        let summaries = apps.map { app -> WidgetAppSummary in
            let s = byApp[app.id]
            return WidgetAppSummary(id: app.id, name: app.name,
                                    version: app.liveVersion?.versionString ?? app.pendingVersion?.versionString ?? "—",
                                    state: app.headlineState,
                                    liveVersion: app.liveVersion?.versionString,
                                    pendingVersion: app.pendingVersion?.versionString,
                                    pendingState: app.pendingVersion?.state,
                                    downloads: hasSales ? (s?.installs ?? 0) : nil,
                                    build: app.latestBuild?.number,
                                    buildState: app.latestBuild.map { $0.needsCompliance ? "MISSING_EXPORT_COMPLIANCE" : $0.displayState },
                                    rating: app.rating,
                                    ratingCount: app.ratingCount,
                                    proceeds: hasSales ? (s?.proceeds ?? 0) : nil,
                                    updates: hasSales ? (s?.updates ?? 0) : nil,
                                    history: hasSales ? perAppHistory[app.id] : nil)
        }
        let series = sales.points.suffix(30).map { $0.installs }
        let total = sales.points.map { HistoryPoint(date: $0.date, value: $0.installs) }
        let snapshot = SharedSnapshot(updated: .now, apps: summaries,
                                      accountName: active?.name,
                                      downloads: hasSales ? sales.installs : nil,
                                      downloadsRange: hasSales ? salesRange.rawValue : nil,
                                      series: series.isEmpty ? nil : Array(series),
                                      proceeds: hasSales ? sales.proceeds : nil,
                                      currency: sales.currency.isEmpty ? nil : sales.currency,
                                      history: total.isEmpty ? nil : total,
                                      updates: hasSales ? sales.updates : nil)
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        PhoneWatchBridge.shared.send(snapshot)
        let top = Array(apps.prefix(20))
        Task {
            await IconExporter.export(apps: top)
            PhoneWatchBridge.shared.send(SharedSnapshot.load())
        }
    }
}

/// Public iTunes Search lookup: App Store artwork, rating and store URL for live apps.
enum StoreLookup {
    struct Info { let artwork: URL?; let rating: Double?; let ratingCount: Int?; let url: URL? }

    private struct Response: Decodable {
        struct Item: Decodable {
            let trackId: Int?
            let artworkUrl512: String?
            let artworkUrl100: String?
            let averageUserRating: Double?
            let userRatingCount: Int?
            let trackViewUrl: String?
        }
        let results: [Item]
    }

    static func fetch(ids: [String]) async -> [String: Info] {
        guard !ids.isEmpty else { return [:] }
        var out: [String: Info] = [:]
        let region = (Locale.current.region?.identifier ?? "nl").lowercased()
        for country in [region, "us"] {
            let missing = ids.filter { out[$0] == nil }
            if missing.isEmpty { break }
            var index = 0
            while index < missing.count {
                let chunk = missing[index..<min(index + 150, missing.count)]
                index += 150
                guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(chunk.joined(separator: ","))&country=\(country)&entity=software") else { continue }
                guard let fetched = try? await URLSession.shared.data(from: url),
                      let res = try? JSONDecoder().decode(Response.self, from: fetched.0) else { continue }
                for item in res.results {
                    guard let id = item.trackId.map(String.init) else { continue }
                    out[id] = Info(artwork: (item.artworkUrl512 ?? item.artworkUrl100).flatMap(URL.init(string:)),
                                   rating: item.averageUserRating, ratingCount: item.userRatingCount,
                                   url: item.trackViewUrl.flatMap(URL.init(string:)))
                }
            }
        }
        return out
    }
}

/// Writes small PNG copies of app icons into the App Group so widgets can show them.
enum IconExporter {
    static func export(apps: [AppSummary]) async {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedSnapshot.suite)?
            .appendingPathComponent("Icons", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for app in apps {
            guard let url = app.iconURL else { continue }
            let file = dir.appendingPathComponent("\(app.id).png")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 86_400 { continue }
            guard let fetched = try? await URLSession.shared.data(from: url), let image = UIImage(data: fetched.0) else { continue }
            let size = CGSize(width: 96, height: 96)
            let renderer = UIGraphicsImageRenderer(size: size)
            let small = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            if let png = small.pngData() { try? png.write(to: file) }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

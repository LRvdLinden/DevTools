import Foundation

/// Downloads / proceeds from App Store Connect Sales and Trends reports
/// (GET /v1/salesReports, SALES · SUMMARY). Needs the vendor number and a key
/// with the Admin, Finance or Sales role. Reports are cached per day on disk.
struct SalesRow: Codable, Hashable {
    let appleID: String
    let parentID: String
    let sku: String
    let title: String
    let type: String
    let units: Int
    let proceeds: Double
    let currency: String
    let country: String
    let device: String

    var kind: SalesKind { SalesKind(type) }
}

enum SalesKind: String, CaseIterable {
    case download, redownload, update, iap, other

    init(_ productType: String) {
        switch productType {
        case "1", "1F", "1T", "F1", "1E", "1EP", "1EU": self = .download
        case "3", "3F", "3T", "F3": self = .redownload
        case "7", "7F", "7T", "F7": self = .update
        case "IA1", "IA9", "IAY", "IAC", "FI1", "IA1-M", "IAY-M", "IA9-M": self = .iap
        default: self = .other
        }
    }

    var label: String {
        switch self {
        case .download: return L("Downloads")
        case .redownload: return L("Herdownloads")
        case .update: return L("Updates")
        case .iap: return L("In-app aankopen")
        case .other: return L("Overig")
        }
    }
}

enum SalesRange: String, CaseIterable, Identifiable {
    case week = "7d", month = "30d", quarter = "90d", year = "1j"
    var id: String { rawValue }
    var label: String { rawValue }
    var title: String {
        switch self {
        case .week: return L("Afgelopen 7 dagen")
        case .month: return L("Afgelopen 30 dagen")
        case .quarter: return L("Afgelopen 90 dagen")
        case .year: return L("Afgelopen jaar (per week)")
        }
    }
    var weekly: Bool { self == .year }
    var count: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 52
        }
    }
}

struct SalesPeriod: Identifiable {
    let date: Date
    let rows: [SalesRow]
    var id: Date { date }
}

struct SalesPoint: Identifiable {
    let date: Date
    var downloads = 0
    var redownloads = 0
    var updates = 0
    var iap = 0
    var proceeds = 0.0
    var id: Date { date }
    var installs: Int { downloads + redownloads }
}

struct AppSales: Identifiable {
    let id: String
    var name: String
    var downloads = 0
    var redownloads = 0
    var updates = 0
    var iap = 0
    var proceeds = 0.0
    var installs: Int { downloads + redownloads }
}

struct ShareItem: Identifiable {
    let id: String
    let label: String
    let value: Int
}

/// Aggregated view of a set of report periods, optionally for one app.
struct SalesSummary {
    var points: [SalesPoint] = []
    var perApp: [AppSales] = []
    var countries: [ShareItem] = []
    var devices: [ShareItem] = []
    var currency = ""
    var multipleCurrencies = false

    var downloads: Int { points.reduce(0) { $0 + $1.downloads } }
    var redownloads: Int { points.reduce(0) { $0 + $1.redownloads } }
    var updates: Int { points.reduce(0) { $0 + $1.updates } }
    var iap: Int { points.reduce(0) { $0 + $1.iap } }
    var proceeds: Double { points.reduce(0) { $0 + $1.proceeds } }
    var installs: Int { downloads + redownloads }
    var best: SalesPoint? { points.max { $0.installs < $1.installs } }
    var average: Double { points.isEmpty ? 0 : Double(installs) / Double(points.count) }
    var isEmpty: Bool { points.allSatisfy { $0.installs == 0 && $0.updates == 0 && $0.iap == 0 } }

    /// Second half vs first half of the period (trend indicator).
    var trend: Int {
        guard points.count >= 4 else { return 0 }
        let half = points.count / 2
        let first = points.prefix(half).reduce(0) { $0 + $1.installs }
        let last = points.suffix(half).reduce(0) { $0 + $1.installs }
        return last - first
    }

    init() {}

    init(periods: [SalesPeriod], apps: [AppSummary], appID: String? = nil) {
        let skuToApp = Dictionary(apps.map { ($0.sku, $0.id) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(apps.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var appTotals: [String: AppSales] = [:]
        var countryTotals: [String: Int] = [:]
        var deviceTotals: [String: Int] = [:]
        var currencyTotals: [String: Double] = [:]

        for period in periods.sorted(by: { $0.date < $1.date }) {
            var p = SalesPoint(date: period.date)
            for row in period.rows {
                let kind = row.kind
                if kind == .other { continue }
                let owner: String
                if kind == .iap { owner = skuToApp[row.parentID] ?? row.parentID } else { owner = row.appleID }
                if let appID, owner != appID { continue }
                let money = row.proceeds * Double(row.units)
                var a = appTotals[owner] ?? AppSales(id: owner, name: names[owner] ?? row.title)
                switch kind {
                case .download: p.downloads += row.units; a.downloads += row.units
                case .redownload: p.redownloads += row.units; a.redownloads += row.units
                case .update: p.updates += row.units; a.updates += row.units
                case .iap: p.iap += row.units; a.iap += row.units
                case .other: break
                }
                if money != 0 {
                    p.proceeds += money
                    a.proceeds += money
                    currencyTotals[row.currency, default: 0] += abs(money)
                }
                appTotals[owner] = a
                if kind == .download || kind == .redownload {
                    countryTotals[row.country, default: 0] += row.units
                    let device = row.device.isEmpty ? "Overig" : row.device
                    deviceTotals[device, default: 0] += row.units
                }
            }
            points.append(p)
        }
        perApp = appTotals.values.sorted { $0.installs == $1.installs ? $0.proceeds > $1.proceeds : $0.installs > $1.installs }
        countries = countryTotals.filter { $0.value > 0 }.map { ShareItem(id: $0.key, label: Fmt.countryName($0.key), value: $0.value) }.sorted { $0.value > $1.value }
        devices = deviceTotals.filter { $0.value > 0 }.map { ShareItem(id: $0.key, label: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
        currency = currencyTotals.max { $0.value < $1.value }?.key ?? ""
        multipleCurrencies = currencyTotals.count > 1
    }
}

enum SalesEngine {
    private static var pacific: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return c
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Report dates for a range (Pacific time, the timezone Apple's reports use).
    static func dates(for range: SalesRange, now: Date = .now) -> [Date] {
        let cal = pacific
        let today = cal.startOfDay(for: now)
        if range.weekly {
            // Weekly reports end on Sunday; use the most recent completed week.
            var lastSunday = cal.date(byAdding: .day, value: -1, to: today) ?? today
            while cal.component(.weekday, from: lastSunday) != 1 {
                lastSunday = cal.date(byAdding: .day, value: -1, to: lastSunday) ?? lastSunday
            }
            return Array((0..<range.count).compactMap { cal.date(byAdding: .day, value: -7 * $0, to: lastSunday) }.reversed())
        }
        return Array((1...range.count).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.reversed())
    }

    private static func cacheURL(vendor: String, weekly: Bool, date: Date) -> URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("SalesReports", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(vendor)-\(weekly ? "W" : "D")-\(dayFormatter.string(from: date)).json"
        return dir.appendingPathComponent(name)
    }

    static func clearCache() {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("SalesReports", isDirectory: true) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    struct Result {
        var periods: [SalesPeriod] = []
        var error: String?
        var missing = 0
    }

    static func load(account: DeveloperAccount, range: SalesRange, progress: (@MainActor (Double) -> Void)? = nil) async -> Result {
        guard let vendor = account.vendorNumber?.trimmingCharacters(in: .whitespaces), !vendor.isEmpty else {
            return Result(error: L("Geen vendornummer ingesteld."))
        }
        let api = ConnectAPI(account: account)
        let dates = dates(for: range)
        var periods: [SalesPeriod] = []
        var firstError: String?
        var missing = 0
        var done = 0
        let chunkSize = 8
        var index = 0
        while index < dates.count {
            let chunk = Array(dates[index..<min(index + chunkSize, dates.count)])
            index += chunkSize
            await withTaskGroup(of: (Date, [SalesRow]?, String?).self) { group in
                for date in chunk {
                    group.addTask { await fetch(api: api, vendor: vendor, date: date, weekly: range.weekly) }
                }
                for await (date, rows, err) in group {
                    done += 1
                    if let rows { periods.append(SalesPeriod(date: date, rows: rows)) }
                    else {
                        missing += 1
                        periods.append(SalesPeriod(date: date, rows: []))
                        if firstError == nil, let err { firstError = err }
                    }
                }
            }
            if let progress { await progress(Double(done) / Double(max(dates.count, 1))) }
            // A wrong key role or vendor number fails every day: stop early.
            if let e = firstError, done >= chunkSize, missing == done { return Result(periods: [], error: e, missing: missing) }
        }
        periods.sort { $0.date < $1.date }
        return Result(periods: periods, error: missing == dates.count ? firstError : nil, missing: missing)
    }

    private static func fetch(api: ConnectAPI, vendor: String, date: Date, weekly: Bool) async -> (Date, [SalesRow]?, String?) {
        let file = cacheURL(vendor: vendor, weekly: weekly, date: date)
        if let file, let data = try? Data(contentsOf: file), let rows = try? JSONDecoder().decode([SalesRow].self, from: data) {
            return (date, rows, nil)
        }
        let query: [(String, String)] = [
            ("filter[frequency]", weekly ? "WEEKLY" : "DAILY"),
            ("filter[reportType]", "SALES"),
            ("filter[reportSubType]", "SUMMARY"),
            ("filter[vendorNumber]", vendor),
            ("filter[reportDate]", dayFormatter.string(from: date)),
            ("filter[version]", "1_0")
        ]
        let ageDays = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        do {
            let tsv = try await api.report("/v1/salesReports", query)
            let rows = parse(tsv)
            if let file, ageDays >= 2, let data = try? JSONEncoder().encode(rows) { try? data.write(to: file) }
            return (date, rows, nil)
        } catch let e as ConnectError where e.status == 404 {
            // 404 = no sales that day (or report not ready yet for the most recent days).
            if let file, ageDays >= (weekly ? 9 : 4), let data = try? JSONEncoder().encode([SalesRow]()) { try? data.write(to: file) }
            return (date, [], nil)
        } catch {
            return (date, nil, error.localizedDescription)
        }
    }

    static func parse(_ tsv: String) -> [SalesRow] {
        var lines = tsv.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
        func col(_ name: String) -> Int? { header.firstIndex(of: name) }
        let iApple = col("Apple Identifier"), iParent = col("Parent Identifier"), iSKU = col("SKU"), iTitle = col("Title")
        let iType = col("Product Type Identifier"), iUnits = col("Units"), iProceeds = col("Developer Proceeds")
        let iCurrency = col("Currency of Proceeds"), iCountry = col("Country Code"), iDevice = col("Device")
        func value(_ f: [String], _ i: Int?) -> String {
            guard let i, i < f.count else { return "" }
            return f[i].trimmingCharacters(in: .whitespaces)
        }
        return lines.compactMap { line in
            let f = line.components(separatedBy: "\t")
            guard f.count > 3 else { return nil }
            return SalesRow(
                appleID: value(f, iApple),
                parentID: value(f, iParent),
                sku: value(f, iSKU),
                title: value(f, iTitle),
                type: value(f, iType),
                units: Int(Double(value(f, iUnits)) ?? 0),
                proceeds: Double(value(f, iProceeds)) ?? 0,
                currency: value(f, iCurrency),
                country: value(f, iCountry),
                device: value(f, iDevice)
            )
        }
    }
}

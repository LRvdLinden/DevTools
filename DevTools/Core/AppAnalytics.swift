import Foundation

/// App Analytics via the Analytics Reports API (impressions, product page views, conversion, sessions,
/// crashes, installs/deletions and an approximated retention).
///
/// Flow: one ONGOING analyticsReportRequest per app → reports (by name) → DAILY instances → segments
/// (pre-signed URLs to gzip TSV files). Instances never change, so every parsed instance is cached on disk.
struct AnalyticsDay: Codable, Hashable {
    var date: String
    var impressions = 0
    var uniqueImpressions = 0
    var pageViews = 0
    var uniquePageViews = 0
    var firstDownloads = 0
    var redownloads = 0
    var updates = 0
    var sessions = 0
    var sessionSeconds: Double = 0
    var activeDevices = 0
    var installs = 0
    var deletions = 0
    var crashes = 0

    mutating func add(_ o: AnalyticsDay) {
        impressions += o.impressions; uniqueImpressions += o.uniqueImpressions
        pageViews += o.pageViews; uniquePageViews += o.uniquePageViews
        firstDownloads += o.firstDownloads; redownloads += o.redownloads; updates += o.updates
        sessions += o.sessions; sessionSeconds += o.sessionSeconds; activeDevices += o.activeDevices
        installs += o.installs; deletions += o.deletions; crashes += o.crashes
    }

    var downloads: Int { firstDownloads + redownloads }
}

/// Unique devices with a session on `date`, for users who downloaded on `downloadDate` (Sessions report).
struct CohortCell: Codable, Hashable {
    var downloadDate: String
    var date: String
    var devices: Int
}

struct AnalyticsResult {
    var days: [AnalyticsDay] = []          // oldest first
    var cohorts: [CohortCell] = []
    var reportsFound: [String] = []

    var total: AnalyticsDay {
        var t = AnalyticsDay(date: "")
        for d in days { t.add(d) }
        return t
    }

    /// Downloads ÷ unique impressions, like App Store Connect's conversion rate.
    var conversion: Double? {
        let t = total
        guard t.uniqueImpressions > 0 else { return nil }
        return Double(t.downloads) / Double(t.uniqueImpressions)
    }

    /// Share of first-time downloaders that had a session N days later (approximation; Apple has no retention report).
    func retention(day n: Int) -> Double? {
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0.firstDownloads) })
        var retained = 0, base = 0
        for (dl, downloads) in byDate where downloads > 0 {
            guard let d = AnalyticsEngine.dayFormatter.date(from: dl),
                  let target = Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: d) else { continue }
            let t = AnalyticsEngine.dayFormatter.string(from: target)
            guard byDate[t] != nil else { continue }
            retained += cohorts.filter { $0.downloadDate == dl && $0.date == t }.reduce(0) { $0 + $1.devices }
            base += downloads
        }
        guard base > 0 else { return nil }
        return min(1, Double(retained) / Double(base))
    }
}

enum AnalyticsKind: String, CaseIterable, Codable {
    case discovery, downloads, sessions, installs, crashes

    /// Picks the best matching report name (Standard preferred over Detailed/Expanded).
    func matches(_ name: String) -> Int? {
        let n = name.lowercased()
        let hit: Bool
        switch self {
        case .discovery: hit = n.contains("discovery and engagement")
        case .downloads: hit = n.hasPrefix("app downloads")
        case .sessions: hit = n.hasPrefix("app sessions")
        case .installs: hit = n.contains("installation and deletion")
        case .crashes: hit = n.hasPrefix("app crashes")
        }
        guard hit else { return nil }
        if n.contains("standard") { return 0 }
        if n.contains("expanded") || n.contains("detailed") { return 2 }
        return 1
    }
}

enum AnalyticsEngine {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    struct InstancePart: Codable {
        var days: [String: AnalyticsDay] = [:]
        var cohorts: [String: CohortCell] = [:]
    }

    // MARK: Requests

    static func ongoingRequest(api: ConnectAPI, appID: String) async throws -> JRes? {
        try await api.jget("/v1/apps/\(appID)/analyticsReportRequests", [("filter[accessType]", "ONGOING")]).data.first
    }

    static func enable(api: ConnectAPI, appID: String) async throws {
        try await api.jcreate("/v1/analyticsReportRequests", type: "analyticsReportRequests",
                              attributes: ["accessType": "ONGOING"], relationships: ["app": ("apps", appID)])
    }

    // MARK: Load

    static func load(api: ConnectAPI, appID: String, requestID: String, days: Int,
                     progress: (@MainActor (Double) -> Void)? = nil) async throws -> AnalyticsResult {
        if api.account.id == DemoData.accountID { return demo(appID: appID, days: days) }
        let reports = try await api.jget("/v1/analyticsReportRequests/\(requestID)/reports", [("limit", "200")], all: true).data
        var chosen: [(AnalyticsKind, JRes)] = []
        for kind in AnalyticsKind.allCases {
            let best = reports.compactMap { r -> (Int, JRes)? in kind.matches(r.str("name")).map { ($0, r) } }.min { $0.0 < $1.0 }
            if let best { chosen.append((kind, best.1)) }
        }
        var result = AnalyticsResult()
        result.reportsFound = chosen.map { $0.1.str("name") }
        guard !chosen.isEmpty else { return result }

        // Instances per report (newest `days` daily instances).
        var jobs: [(AnalyticsKind, JRes)] = []
        for (kind, report) in chosen {
            let inst = try await api.jget("/v1/analyticsReports/\(report.id)/instances", [("filter[granularity]", "DAILY"), ("limit", "200")], all: true, max: 400).data
            let recent = inst.sorted { $0.str("processingDate") > $1.str("processingDate") }.prefix(days)
            jobs += recent.map { (kind, $0) }
        }

        var merged: [String: AnalyticsDay] = [:]
        var cohorts: [String: CohortCell] = [:]
        var done = 0
        var i = 0
        while i < jobs.count {
            let chunk = Array(jobs[i..<min(i + 6, jobs.count)])
            i += 6
            await withTaskGroup(of: InstancePart?.self) { group in
                for (kind, instance) in chunk {
                    group.addTask { try? await part(api: api, kind: kind, instance: instance) }
                }
                for await part in group {
                    done += 1
                    guard let part else { continue }
                    for (date, d) in part.days {
                        var cur = merged[date] ?? AnalyticsDay(date: date)
                        cur.add(d)
                        merged[date] = cur
                    }
                    for (k, c) in part.cohorts {
                        var cur = cohorts[k] ?? CohortCell(downloadDate: c.downloadDate, date: c.date, devices: 0)
                        cur.devices += c.devices
                        cohorts[k] = cur
                    }
                }
            }
            if let progress { await progress(Double(done) / Double(max(jobs.count, 1))) }
        }
        result.days = merged.values.sorted { $0.date < $1.date }.suffix(days).map { $0 }
        result.cohorts = Array(cohorts.values)
        return result
    }

    private static var cacheDir: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("analytics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func clearCache() {
        if let dir = cacheDir { try? FileManager.default.removeItem(at: dir) }
    }

    /// Downloads and aggregates one instance (all its segments); cached on disk.
    private static func part(api: ConnectAPI, kind: AnalyticsKind, instance: JRes) async throws -> InstancePart {
        let file = cacheDir?.appendingPathComponent("\(kind.rawValue)-\(instance.id).json")
        if let file, let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(InstancePart.self, from: data) {
            return cached
        }
        let segments = try await api.jget("/v1/analyticsReportInstances/\(instance.id)/segments", [("limit", "200")], all: true).data
        var part = InstancePart()
        for seg in segments {
            guard let s = seg.s("url"), let url = URL(string: s) else { continue }
            let (raw, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode ?? 200 < 300 else { continue }
            let text = String(decoding: try Gzip.decompress(raw), as: UTF8.self)
            aggregate(kind: kind, rows: parseTable(text), into: &part)
        }
        if let file, let data = try? JSONEncoder().encode(part) { try? data.write(to: file) }
        return part
    }

    // MARK: Parsing

    /// Parses TSV (or CSV for "Expanded" reports) into dictionaries keyed by lower-cased header.
    static func parseTable(_ text: String) -> [[String: String]] {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }
        let headerLine = lines.removeFirst()
        let tab = headerLine.contains("\t")
        let header = split(headerLine, tab: tab).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return lines.map { line in
            let f = split(line, tab: tab)
            var row: [String: String] = [:]
            for (i, h) in header.enumerated() where i < f.count { row[h] = f[i].trimmingCharacters(in: .whitespaces) }
            return row
        }
    }

    private static func split(_ line: String, tab: Bool) -> [String] {
        if tab { return line.components(separatedBy: "\t") }
        var out: [String] = [], cur = "", quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle() }
            else if ch == "," && !quoted { out.append(cur); cur = "" }
            else { cur.append(ch) }
        }
        out.append(cur)
        return out
    }

    private static func num(_ row: [String: String], _ keys: String...) -> Double {
        for k in keys {
            if let v = row[k], let d = Double(v.replacingOccurrences(of: ",", with: "")) { return d }
        }
        // Prefix match, e.g. "total session duration (seconds)".
        for k in keys {
            if let entry = row.first(where: { $0.key.hasPrefix(k) }), let d = Double(entry.value) { return d }
        }
        return 0
    }

    static func aggregate(kind: AnalyticsKind, rows: [[String: String]], into part: inout InstancePart) {
        for row in rows {
            let date = String((row["date"] ?? "").prefix(10))
            guard !date.isEmpty else { continue }
            var d = part.days[date] ?? AnalyticsDay(date: date)
            switch kind {
            case .discovery:
                let event = (row["event"] ?? "").lowercased()
                let counts = Int(num(row, "counts")), unique = Int(num(row, "unique counts"))
                if event == "impression" { d.impressions += counts; d.uniqueImpressions += unique }
                else if event == "page view" { d.pageViews += counts; d.uniquePageViews += unique }
            case .downloads:
                let type = (row["download type"] ?? "").lowercased()
                let counts = Int(num(row, "counts"))
                if type.hasPrefix("first-time") { d.firstDownloads += counts }
                else if type == "redownload" { d.redownloads += counts }
                else if type.contains("update") { d.updates += counts }
            case .sessions:
                d.sessions += Int(num(row, "sessions"))
                d.sessionSeconds += num(row, "total session duration")
                let devices = Int(num(row, "unique devices"))
                d.activeDevices += devices
                if let dl = row["app download date"], dl.count >= 10 {
                    let key = String(dl.prefix(10)) + "|" + date
                    var c = part.cohorts[key] ?? CohortCell(downloadDate: String(dl.prefix(10)), date: date, devices: 0)
                    c.devices += devices
                    part.cohorts[key] = c
                }
            case .installs:
                let event = (row["event"] ?? "").lowercased()
                let counts = Int(num(row, "counts"))
                if event == "install" { d.installs += counts } else if event == "delete" { d.deletions += counts }
            case .crashes:
                d.crashes += Int(num(row, "crashes", "crash count", "count"))
            }
            part.days[date] = d
        }
    }

    // MARK: Demo

    static func demo(appID: String, days: Int) -> AnalyticsResult {
        var seed = appID.unicodeScalars.reduce(11) { ($0 &* 31 &+ Int($1.value)) % 100_003 }
        func rnd(_ range: ClosedRange<Int>) -> Int { seed = (seed &* 1_103_515_245 &+ 12_345) % 2_147_483_647; return range.lowerBound + abs(seed) % (range.count) }
        var result = AnalyticsResult()
        let cal = Calendar(identifier: .gregorian)
        for n in stride(from: days + 2, through: 3, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -n, to: .now) else { continue }
            let key = dayFormatter.string(from: date)
            let base = 900 + rnd(0...700) + (days - n) * 12
            var d = AnalyticsDay(date: key)
            d.impressions = base * 3; d.uniqueImpressions = base * 2
            d.pageViews = base / 3; d.uniquePageViews = base / 4
            d.firstDownloads = base / 14 + rnd(0...20); d.redownloads = base / 60
            d.updates = rnd(40...160)
            d.sessions = base + rnd(0...400); d.sessionSeconds = Double(d.sessions * rnd(90...260)); d.activeDevices = base / 2
            d.installs = d.firstDownloads + d.redownloads; d.deletions = rnd(2...14); d.crashes = rnd(0...4)
            result.days.append(d)
        }
        for (i, d) in result.days.enumerated() {
            for lag in [1, 7] where i + lag < result.days.count {
                result.cohorts.append(CohortCell(downloadDate: d.date, date: result.days[i + lag].date,
                                                 devices: Int(Double(d.firstDownloads) * (lag == 1 ? 0.42 : 0.19))))
            }
        }
        result.reportsFound = ["App Store Discovery and Engagement Standard", "App Downloads Standard", "App Sessions Standard",
                               "App Store Installation and Deletion Standard", "App Crashes"]
        return result
    }
}

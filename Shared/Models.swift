import Foundation

/// Snapshot shared with the widgets (App Group) and the Apple Watch (WatchConnectivity).
/// The app writes it after every refresh; widgets and watch only read it, so they never
/// need the API key. New fields are optional so older snapshots keep decoding.
struct HistoryPoint: Codable, Hashable {
    var date: Date
    var value: Int
}

struct WidgetAppSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let state: String
    var liveVersion: String? = nil
    var pendingVersion: String? = nil
    var pendingState: String? = nil
    var downloads: Int? = nil
    var build: String? = nil
    var buildState: String? = nil
    var rating: Double? = nil
    var ratingCount: Int? = nil
    var proceeds: Double? = nil
    var updates: Int? = nil
    /// Daily installs (new + re-downloads) for the selected range.
    var history: [HistoryPoint]? = nil

    var isLive: Bool { liveVersion != nil || state == "READY_FOR_SALE" }
    /// Only "Ready for Sale" is Live; "Ready for Distribution" is the step before.
    var statusLabel: String { SharedSnapshot.label(for: state) }
    var activeState: String { pendingState ?? state }
    var inReview: Bool { ["WAITING_FOR_REVIEW", "IN_REVIEW"].contains(activeState) }
    var needsAttention: Bool {
        ["REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "PENDING_DEVELOPER_RELEASE", "READY_FOR_DISTRIBUTION"].contains(activeState)
            || buildState == "MISSING_EXPORT_COMPLIANCE"
    }
    var series: [HistoryPoint] { history ?? [] }
    var last7: Int? { HistoryMath.sum(series, last: 7) }
    var delta7: Int? { HistoryMath.delta(series, days: 7) }
}

enum HistoryMath {
    static func sum(_ h: [HistoryPoint], last days: Int) -> Int? {
        guard !h.isEmpty else { return nil }
        return h.suffix(days).reduce(0) { $0 + $1.value }
    }

    /// Last `days` days compared with the `days` days before.
    static func delta(_ h: [HistoryPoint], days: Int) -> Int? {
        guard h.count >= days * 2 else { return nil }
        let recent = h.suffix(days).reduce(0) { $0 + $1.value }
        let before = h.dropLast(days).suffix(days).reduce(0) { $0 + $1.value }
        return recent - before
    }
}

struct SharedSnapshot: Codable {
    let updated: Date
    let apps: [WidgetAppSummary]
    var accountName: String? = nil
    var downloads: Int? = nil
    var downloadsRange: String? = nil
    var series: [Int]? = nil
    var proceeds: Double? = nil
    var currency: String? = nil
    var history: [HistoryPoint]? = nil
    var updates: Int? = nil

    var inReviewApps: [WidgetAppSummary] { apps.filter(\.inReview) }
    var inReview: Int { inReviewApps.count }
    var attentionApps: [WidgetAppSummary] { apps.filter(\.needsAttention) }
    var liveCount: Int { apps.filter(\.isLive).count }
    var totalHistory: [HistoryPoint] { history ?? [] }
    var total7: Int? { HistoryMath.sum(totalHistory, last: 7) }
    var delta7: Int? { HistoryMath.delta(totalHistory, days: 7) }
    var topApps: [WidgetAppSummary] { apps.sorted { ($0.downloads ?? -1) > ($1.downloads ?? -1) } }
    var averageRating: Double? {
        let rated = apps.compactMap { a -> (Double, Int)? in
            guard let r = a.rating, let c = a.ratingCount, c > 0 else { return nil }
            return (r, c)
        }
        let n = rated.reduce(0) { $0 + $1.1 }
        guard n > 0 else { return nil }
        return rated.reduce(0.0) { $0 + $1.0 * Double($1.1) } / Double(n)
    }
    func app(_ id: String?) -> WidgetAppSummary? {
        guard let id else { return nil }
        return apps.first { $0.id == id }
    }

    static let placeholder = SharedSnapshot(updated: .now, apps: [])
    static let suite = "group.nl.lrvdlinden.devtools"
    static let watchSuite = "group.nl.lrvdlinden.devtools.watch"

    static func load(suite: String = SharedSnapshot.suite, key: String = "snapshot") -> SharedSnapshot {
        guard let d = UserDefaults(suiteName: suite)?.data(forKey: key),
              let value = try? JSONDecoder().decode(Self.self, from: d) else { return .placeholder }
        return value
    }

    func save() { UserDefaults(suiteName: Self.suite)?.set(try? JSONEncoder().encode(self), forKey: "snapshot") }

    static func label(for state: String) -> String {
        switch state {
        case "READY_FOR_SALE": return "Live"
        case "READY_FOR_DISTRIBUTION": return "Klaar voor distributie"
        case "WAITING_FOR_REVIEW": return "Wacht op review"
        case "IN_REVIEW": return "In review"
        case "READY_FOR_REVIEW": return "Klaar voor review"
        case "PREPARE_FOR_SUBMISSION": return "Voorbereiden"
        case "PENDING_DEVELOPER_RELEASE": return "Klaar voor release"
        case "PENDING_APPLE_RELEASE": return "Wacht op Apple"
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": return "Afgewezen"
        case "DEVELOPER_REJECTED": return "Teruggetrokken"
        case "PROCESSING_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE": return "Verwerken"
        case "MISSING_EXPORT_COMPLIANCE": return "Export compliance"
        case "", "—": return "—"
        default: return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Icons live in the App Group of the device (iPhone: shared group, Watch: watch group).
    static func iconURL(for appID: String, suite: String = SharedSnapshot.suite) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite)?
            .appendingPathComponent("Icons", isDirectory: true)
            .appendingPathComponent("\(appID).png")
    }
}

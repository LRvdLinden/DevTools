import Foundation

/// Snapshot shared with the widgets (App Group) and the Apple Watch (WatchConnectivity).
/// New fields are optional so older snapshots keep decoding.
struct WidgetAppSummary: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let state: String
    var liveVersion: String? = nil
    var pendingVersion: String? = nil
    var pendingState: String? = nil
    var downloads: Int? = nil
    var build: String? = nil

    var isLive: Bool { liveVersion != nil || state == "READY_FOR_SALE" }

    /// Human status: only "Ready for Sale" is Live; "Ready for Distribution" is the step before.
    var statusLabel: String { SharedSnapshot.label(for: state) }
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

    var inReview: Int { apps.filter { ["WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW"].contains($0.state) || $0.state.localizedCaseInsensitiveContains("REVIEW") }.count }
    var liveCount: Int { apps.filter(\.isLive).count }

    static let placeholder = SharedSnapshot(updated: .now, apps: [])
    static let suite = "group.nl.lrvdlinden.devtools"

    static func load() -> SharedSnapshot {
        guard let d = UserDefaults(suiteName: suite)?.data(forKey: "snapshot"),
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
        case "", "—": return "—"
        default: return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func iconURL(for appID: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite)?
            .appendingPathComponent("Icons", isDirectory: true)
            .appendingPathComponent("\(appID).png")
    }
}

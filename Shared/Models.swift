import Foundation
import ObjectiveC

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
    /// Language chosen in the iPhone app (rawValue of AppLanguage), mirrored on the watch.
    var language: String? = nil

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
        case "READY_FOR_SALE": return L("Live")
        case "READY_FOR_DISTRIBUTION": return L("Klaar voor distributie")
        case "WAITING_FOR_REVIEW": return L("Wacht op review")
        case "IN_REVIEW": return L("In review")
        case "READY_FOR_REVIEW": return L("Klaar voor review")
        case "PREPARE_FOR_SUBMISSION": return L("Voorbereiden")
        case "PENDING_DEVELOPER_RELEASE": return L("Klaar voor release")
        case "PENDING_APPLE_RELEASE": return L("Wacht op Apple")
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": return L("Afgewezen")
        case "DEVELOPER_REJECTED": return L("Teruggetrokken")
        case "PROCESSING_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE": return L("Verwerken")
        case "MISSING_EXPORT_COMPLIANCE": return L("Export compliance")
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

// MARK: - Localization (English default + nl, de, fr, es, pl, nb, da, sv; Dutch source strings are the keys)

/// Languages the app ships with. `system` follows the device (falls back to English).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, nl, de, fr, es, pl, nb, da, sv
    var id: String { rawValue }

    /// Name in the language itself, so everyone can find their own language.
    var nativeName: String {
        switch self {
        case .system: return LS("Automatisch (toestel)")
        case .en: return "English"
        case .nl: return "Nederlands"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .pl: return "Polski"
        case .nb: return "Norsk"
        case .da: return "Dansk"
        case .sv: return "Svenska"
        }
    }

    var flag: String {
        switch self {
        case .system: return "🌐"
        case .en: return "🇬🇧"
        case .nl: return "🇳🇱"
        case .de: return "🇩🇪"
        case .fr: return "🇫🇷"
        case .es: return "🇪🇸"
        case .pl: return "🇵🇱"
        case .nb: return "🇳🇴"
        case .da: return "🇩🇰"
        case .sv: return "🇸🇪"
        }
    }
}

/// In-app language switching. The choice is stored in the App Group so the widgets
/// (and, via the snapshot, the Apple Watch) use the same language.
enum LanguageManager {
    static let key = "appLanguage"

    static var defaults: UserDefaults {
        #if os(watchOS)
        return UserDefaults(suiteName: SharedSnapshot.watchSuite) ?? .standard
        #else
        return UserDefaults(suiteName: SharedSnapshot.suite) ?? .standard
        #endif
    }

    static var selected: AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: key) ?? "") ?? .system
    }

    /// Bundle used for lookups: the chosen .lproj, or the main bundle (device language, English fallback).
    private(set) static var bundle: Bundle = Bundle.main

    /// Locale for formatting (dates, numbers) that matches the chosen language.
    static var locale: Locale {
        selected == .system ? Locale.autoupdatingCurrent : Locale(identifier: selected.rawValue)
    }

    static func set(_ language: AppLanguage) {
        defaults.set(language == .system ? nil : language.rawValue, forKey: key)
        apply()
    }

    /// Applies the stored choice: overrides Bundle.main lookups (SwiftUI Text, NSLocalizedString)
    /// and AppleLanguages (system texts after the next launch).
    static func apply() {
        let lang = selected
        if lang == .system {
            bundle = Bundle.main
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            if let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"), let b = Bundle(path: path) {
                bundle = b
            } else {
                bundle = Bundle.main
            }
            UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
        }
        LocalizedBundle.install()
    }
}

/// Bundle.main subclass that redirects string lookups to the selected language.
private final class LocalizedBundle: Bundle {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        object_setClass(Bundle.main, LocalizedBundle.self)
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let target = LanguageManager.bundle
        if target !== self && target.bundlePath != self.bundlePath {
            return target.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

/// Localized string with interpolation support (keys get %@ / %lld specifiers).
func L(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: LanguageManager.bundle, locale: LanguageManager.locale)
}

/// Runtime lookup for a string that is already held in a variable.
func LS(_ key: String) -> String { LanguageManager.bundle.localizedString(forKey: key, value: nil, table: nil) }

// MARK: - Sample data (widget gallery, watch demo, previews)

extension SharedSnapshot {
    static var sample: SharedSnapshot {
        let cal = Calendar.current
        func hist(_ base: Int, _ phase: Double) -> [HistoryPoint] {
            (0..<30).map { i in
                HistoryPoint(date: cal.date(byAdding: .day, value: i - 30, to: .now) ?? .now,
                             value: base + Int(Double(base) * 0.12 * sin(Double(i) / 3 + phase)) + i * base / 14)
            }
        }
        let a = hist(150, 0), b = hist(70, 1), c = hist(46, 2), d = hist(26, 3), e = hist(15, 4)
        var total: [HistoryPoint] = []
        for i in a.indices { total.append(HistoryPoint(date: a[i].date, value: a[i].value + b[i].value + c[i].value + d[i].value + e[i].value)) }
        func sum(_ h: [HistoryPoint]) -> Int { h.reduce(0) { $0 + $1.value } }
        return SharedSnapshot(
            updated: .now,
            apps: [
                WidgetAppSummary(id: "6740000001", name: "Bingr", version: "1.0.0", state: "IN_REVIEW", liveVersion: "1.0.0", pendingVersion: "1.1.0", pendingState: "IN_REVIEW", downloads: sum(a), build: "142", rating: 4.8, ratingCount: 1284, proceeds: 812, updates: 9_400, history: a),
                WidgetAppSummary(id: "6740000002", name: "Pitwall", version: "1.1.0", state: "PENDING_DEVELOPER_RELEASE", liveVersion: "1.1.0", pendingVersion: "1.2.0", pendingState: "PENDING_DEVELOPER_RELEASE", downloads: sum(b), build: "58", rating: 4.7, ratingCount: 532, proceeds: 0, updates: 4_100, history: b),
                WidgetAppSummary(id: "6740000003", name: "Manga Vault", version: "1.2.1", state: "PREPARE_FOR_SUBMISSION", liveVersion: "1.2.1", pendingVersion: "1.3.0", pendingState: "PREPARE_FOR_SUBMISSION", downloads: sum(c), build: "37", rating: 4.6, ratingCount: 318, proceeds: 2_330, updates: 2_900, history: c),
                WidgetAppSummary(id: "6740000004", name: "TVArt", version: "1.4.0", state: "READY_FOR_DISTRIBUTION", liveVersion: "1.4.0", pendingVersion: "2.0.0", pendingState: "READY_FOR_DISTRIBUTION", downloads: sum(d), build: "24", rating: 4.9, ratingCount: 147, proceeds: 0, updates: 1_200, history: d),
                WidgetAppSummary(id: "6740000005", name: "HomeyDev", version: "1.3.7", state: "METADATA_REJECTED", liveVersion: "1.3.7", pendingVersion: "1.4.0", pendingState: "METADATA_REJECTED", downloads: sum(e), build: "88", rating: 4.5, ratingCount: 96, proceeds: 0, updates: 700, history: e),
                WidgetAppSummary(id: "6740000006", name: "World Radio", version: "1.0.0", state: "WAITING_FOR_REVIEW", pendingVersion: "1.0.0", pendingState: "WAITING_FOR_REVIEW", build: "9")
            ],
            accountName: "PixelForges", downloads: sum(total), downloadsRange: "30d",
            proceeds: 3_142, currency: "EUR", history: total, updates: 18_300)
    }

    /// Asset name of the bundled demo icon for a sample app (watch demo).
    static func demoIcon(for name: String) -> String? {
        switch name {
        case "Bingr": return "demo-bingr"
        case "Pitwall": return "demo-pitwall"
        case "Manga Vault": return "demo-manga"
        case "TVArt": return "demo-tvart"
        case "HomeyDev": return "demo-homey"
        case "World Radio": return "demo-radio"
        default: return nil
        }
    }
}

import SwiftUI
import StoreKit

/// Asks for an App Store rating at a quiet moment:
/// - first time 4 hours after the first use on this device,
/// - after that at most once a week,
/// - only a few seconds after opening, never during the splash or welcome screen, in demo mode,
///   while a sheet (e.g. a push notification) is open, or before at least one account has apps.
/// Apple decides whether the prompt is actually shown (max. 3× per 365 days per app).
@MainActor
enum ReviewPrompter {
    private static let defaults = UserDefaults.standard
    private static let firstUseKey = "review.firstUse"
    private static let lastAskKey = "review.lastAsk"
    static let firstDelay: TimeInterval = 4 * 3600
    static let interval: TimeInterval = 7 * 86400
    static let settle: Duration = .seconds(4)

    /// Call once at launch.
    static func markFirstUse() {
        if defaults.object(forKey: firstUseKey) == nil { defaults.set(Date(), forKey: firstUseKey) }
    }

    static func isDue(now: Date = .now) -> Bool {
        guard let first = defaults.object(forKey: firstUseKey) as? Date, now.timeIntervalSince(first) >= firstDelay else { return false }
        if let last = defaults.object(forKey: lastAskKey) as? Date, now.timeIntervalSince(last) < interval { return false }
        return true
    }

    /// Waits a few seconds, re-checks that the app is still in a quiet state, then asks.
    static func considerAsking(store: DevStore, isQuiet: @escaping @MainActor () -> Bool, request: RequestReviewAction) async {
        guard isDue(), !store.isDemo, store.active != nil, !store.apps.isEmpty, isQuiet() else { return }
        try? await Task.sleep(for: settle)
        guard !Task.isCancelled, isDue(), !store.apps.isEmpty, isQuiet() else { return }
        defaults.set(Date(), forKey: lastAskKey)
        request()
    }
}

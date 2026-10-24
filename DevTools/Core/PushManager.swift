import Foundation
import UIKit
import UserNotifications
import OneSignalFramework

/// Push notifications for App Store Connect events (OneSignal SDK).
///
/// Flow: OneSignal registers the device (APNs) and is logged in with a random per-install key (external_id).
/// The DevTools push relay (Cloudflare Worker) returns a webhook URL + secret for that key; DevTools creates an
/// App Store Connect webhook per app with it. Apple → relay (checks the signature) → OneSignal → this device.
/// The relay stores nothing and the App Store Connect API key never leaves the device.
@MainActor
@Observable
final class PushManager {
    static let shared = PushManager()

    var enabled: Bool = UserDefaults.standard.bool(forKey: "push.enabled")
    var authorized = false
    var working = false
    var error: String?
    var subscriptionID: String?
    var registration: Registration? = PushManager.loadRegistration()

    struct Registration: Codable {
        var webhookURL: String
        var secret: String
    }

    @ObservationIgnored private var observer: SubscriptionObserver?

    static var oneSignalAppID: String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "OneSignalAppID") as? String, !s.isEmpty else { return nil }
        return s
    }

    /// Relay URL from Info.plist (DevToolsPushRelay), e.g. https://devtools-push.<account>.workers.dev
    static var relayURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "DevToolsPushRelay") as? String,
              !s.isEmpty, !s.contains("REPLACE"), let u = URL(string: s) else { return nil }
        return u
    }
    var isConfigured: Bool { Self.relayURL != nil && Self.oneSignalAppID != nil }

    /// Random, per-install key (OneSignal external_id). Not linked to Apple ID, e-mail or App Store Connect account.
    var deviceKey: String {
        if let k = Vault.read("push.deviceKey") { return k }
        let k = UUID().uuidString.lowercased()
        try? Vault.save(k, key: "push.deviceKey")
        return k
    }

    /// Called once at launch (DevToolsApp.init).
    static func initialize() {
        guard let appID = oneSignalAppID else { return }
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_WARN)
        #endif
        OneSignal.initialize(appID, withLaunchOptions: nil)
        Task { @MainActor in shared.startObserving() }
    }

    private func startObserving() {
        let obs = SubscriptionObserver { [weak self] id in self?.subscriptionID = id }
        observer = obs   // OneSignal keeps observers weakly
        OneSignal.User.pushSubscription.addObserver(obs)
        subscriptionID = Self.validID(OneSignal.User.pushSubscription.id)
        if enabled { OneSignal.login(deviceKey) }
    }

    static func validID(_ id: String?) -> String? {
        guard let id, !id.isEmpty, !id.hasPrefix("local-") else { return nil }
        return id
    }

    func refreshAuthorization() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Asks permission (only on the user's tap), logs in to OneSignal and gets the webhook URL from the relay.
    func enable() async -> Bool {
        guard let relay = Self.relayURL, Self.oneSignalAppID != nil else { error = L("Pushmeldingen zijn nog niet ingesteld in deze build."); return false }
        working = true
        defer { working = false }
        let granted = await withCheckedContinuation { cont in
            OneSignal.Notifications.requestPermission({ accepted in cont.resume(returning: accepted) }, fallbackToSettings: true)
        }
        guard granted else { error = L("Meldingen zijn uitgeschakeld voor DevTools in Instellingen."); return false }
        authorized = true
        OneSignal.login(deviceKey)
        OneSignal.User.pushSubscription.optIn()
        do {
            var req = URLRequest(url: relay.appendingPathComponent("register"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["key": deviceKey,
                                                                       "language": LanguageManager.locale.language.languageCode?.identifier ?? "en"])
            req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let reg = try? JSONDecoder().decode(Registration.self, from: data) else {
                throw ConnectError(message: L("De pushserver gaf een fout: \(String(decoding: data.prefix(200), as: UTF8.self))"))
            }
            registration = reg
            Self.saveRegistration(reg)
            enabled = true
            UserDefaults.standard.set(true, forKey: "push.enabled")
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func disable() {
        enabled = false
        UserDefaults.standard.set(false, forKey: "push.enabled")
        OneSignal.User.pushSubscription.optOut()
    }

    private static func loadRegistration() -> Registration? {
        guard let raw = Vault.read("push.registration"), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Registration.self, from: data)
    }

    private static func saveRegistration(_ r: Registration) {
        if let data = try? JSONEncoder().encode(r) { try? Vault.save(String(decoding: data, as: UTF8.self), key: "push.registration") }
    }
}

/// Strongly held by PushManager; forwards OneSignal push subscription changes.
final class SubscriptionObserver: NSObject, OSPushSubscriptionObserver {
    private let onChange: @MainActor (String?) -> Void
    init(_ onChange: @escaping @MainActor (String?) -> Void) { self.onChange = onChange }

    func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
        let id = PushManager.validID(state.current.id)
        Task { @MainActor in onChange(id) }
    }
}

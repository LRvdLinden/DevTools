import Foundation
import UIKit
import UserNotifications

/// Push notifications for App Store Connect events.
///
/// Flow: the device registers with APNs → its token goes to the DevTools push relay (a Cloudflare Worker),
/// which links it to a random device key in OneSignal and returns a webhook URL + secret for that key.
/// DevTools then creates an App Store Connect webhook per app with that URL. Apple → relay (checks the
/// signature) → OneSignal → this device. The relay stores nothing; the API key never leaves the device.
@MainActor
@Observable
final class PushManager {
    static let shared = PushManager()

    var enabled: Bool = UserDefaults.standard.bool(forKey: "push.enabled")
    var authorized = false
    var working = false
    var error: String?
    var registration: Registration? = PushManager.loadRegistration()

    struct Registration: Codable {
        var webhookURL: String
        var secret: String
    }

    /// Relay URL from Info.plist (DevToolsPushRelay), e.g. https://devtools-push.<account>.workers.dev
    static var relayURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "DevToolsPushRelay") as? String,
              !s.isEmpty, !s.contains("REPLACE"), let u = URL(string: s) else { return nil }
        return u
    }
    var isConfigured: Bool { Self.relayURL != nil }

    /// Random, per-install key. Not linked to Apple ID, e-mail or App Store Connect account.
    var deviceKey: String {
        if let k = Vault.read("push.deviceKey") { return k }
        let k = UUID().uuidString.lowercased()
        try? Vault.save(k, key: "push.deviceKey")
        return k
    }

    private var tokenContinuation: CheckedContinuation<String, Error>?

    func refreshAuthorization() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorized = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Asks permission, gets the APNs token and registers it with the relay.
    func enable() async -> Bool {
        guard let relay = Self.relayURL else { error = L("Pushmeldingen zijn nog niet ingesteld in deze build."); return false }
        working = true
        defer { working = false }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { error = L("Meldingen zijn uitgeschakeld voor DevTools in Instellingen."); return false }
            authorized = true
            let token = try await apnsToken()
            #if DEBUG
            let sandbox = true
            #else
            let sandbox = false
            #endif
            var req = URLRequest(url: relay.appendingPathComponent("register"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["key": deviceKey, "token": token, "sandbox": sandbox,
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
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    private func apnsToken() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            tokenContinuation?.resume(throwing: CancellationError())
            tokenContinuation = cont
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        tokenContinuation?.resume(returning: hex)
        tokenContinuation = nil
    }

    func didFail(_ error: Error) {
        tokenContinuation?.resume(throwing: error)
        tokenContinuation = nil
    }

    private static func loadRegistration() -> Registration? {
        guard let raw = Vault.read("push.registration"), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Registration.self, from: data)
    }

    private static func saveRegistration(_ r: Registration) {
        if let data = try? JSONEncoder().encode(r) { try? Vault.save(String(decoding: data, as: UTF8.self), key: "push.registration") }
    }
}

/// UIKit hooks for APNs registration and foreground presentation.
final class DevToolsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if UserDefaults.standard.bool(forKey: "push.enabled") { application.registerForRemoteNotifications() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didRegister(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushManager.shared.didFail(error) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

import UserNotifications
import CryptoKit
import Security
import OneSignalExtension

/// OneSignal Notification Service Extension.
/// Before handing the notification to OneSignal (images, badges, confirmed delivery), DevTools looks up the
/// version, build number and platform with the App Store Connect API key from the shared Keychain group,
/// like Apple's own notifications: "Trailhead (iOS)" · "2.5.0 (318)".
class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var receivedRequest: UNNotificationRequest!
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.receivedRequest = request
        self.contentHandler = contentHandler
        self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        guard let content = bestAttemptContent else { contentHandler(request.content); return }
        Task {
            await Enricher.enrich(content)
            OneSignalExtension.didReceiveNotificationExtensionRequest(self.receivedRequest, with: content, withContentHandler: contentHandler)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            OneSignalExtension.serviceExtensionTimeWillExpireRequest(receivedRequest, with: bestAttemptContent)
            contentHandler(bestAttemptContent)
        }
    }
}

/// Adds platform, version and build to DevTools notifications.
enum Enricher {
    static let appGroup = "group.nl.lrvdlinden.devtools"

    /// Custom data sent by the relay (OneSignal puts it under custom.a).
    static func data(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        if let custom = userInfo["custom"] as? [String: Any], let a = custom["a"] as? [String: Any] { return a }
        return userInfo as? [String: Any] ?? [:]
    }

    static func enrich(_ content: UNMutableNotificationContent) async {
        let d = data(content.userInfo)
        guard let event = d["event"] as? String, let instance = d["instanceId"] as? String, !instance.isEmpty else { return }
        let appName = d["app"] as? String ?? content.title
        let path: String
        switch event {
        case "appStoreVersionAppVersionStateUpdated":
            path = "/v1/appStoreVersions/\(instance)?fields[appStoreVersions]=versionString,platform"
        case "buildUploadStateUpdated":
            path = "/v1/builds/\(instance)?include=preReleaseVersion&fields[builds]=version,preReleaseVersion"
        case "buildBetaDetailExternalBuildStateUpdated":
            path = "/v1/buildBetaDetails/\(instance)/build?include=preReleaseVersion&fields[builds]=version,preReleaseVersion"
        case "betaFeedbackScreenshotSubmissionCreated":
            path = "/v1/betaFeedbackScreenshotSubmissions/\(instance)?include=build"
        case "betaFeedbackCrashSubmissionCreated":
            path = "/v1/betaFeedbackCrashSubmissions/\(instance)?include=build"
        default:
            return
        }
        guard let doc = await get(path), let item = (doc["data"] as? [String: Any]) else { return }
        let attrs = item["attributes"] as? [String: Any] ?? [:]
        let included = doc["included"] as? [[String: Any]] ?? []
        func inc(_ type: String) -> [String: Any]? {
            (included.first { $0["type"] as? String == type })?["attributes"] as? [String: Any]
        }

        var platform = ""
        var subtitle = ""
        switch event {
        case "appStoreVersionAppVersionStateUpdated":
            platform = attrs["platform"] as? String ?? ""
            if let v = attrs["versionString"] as? String { subtitle = v }
        case "buildUploadStateUpdated", "buildBetaDetailExternalBuildStateUpdated":
            let pre = inc("preReleaseVersions")
            platform = pre?["platform"] as? String ?? ""
            let number = attrs["version"] as? String ?? ""
            let version = pre?["version"] as? String ?? ""
            subtitle = version.isEmpty ? number : "\(version) (\(number))"
        default:   // feedback
            platform = attrs["appPlatform"] as? String ?? ""
            if let b = inc("builds"), let n = b["version"] as? String { subtitle = n }
            if let comment = attrs["comment"] as? String, !comment.isEmpty {
                content.body = comment
            }
            if let device = attrs["deviceModel"] as? String {
                subtitle = subtitle.isEmpty ? device : "\(subtitle) · \(device)"
            }
        }
        let label = platformLabel(platform)
        if !label.isEmpty { content.title = "\(appName) (\(label))" }
        if !subtitle.isEmpty { content.subtitle = subtitle }
    }

    static func platformLabel(_ p: String) -> String {
        switch p {
        case "IOS": return "iOS"
        case "MAC_OS": return "macOS"
        case "TV_OS": return "tvOS"
        case "VISION_OS": return "visionOS"
        case "WATCH_OS": return "watchOS"
        default: return ""
        }
    }

    // MARK: App Store Connect (read-only, own JWT)

    struct Account { let id: String; let issuer: String; let key: String }

    static func accounts() -> [Account] {
        let list = UserDefaults(suiteName: appGroup)?.array(forKey: "push.accounts") as? [[String: String]] ?? []
        return list.compactMap { d in
            guard let id = d["id"], let issuer = d["issuer"], let key = d["key"] else { return nil }
            return Account(id: id, issuer: issuer, key: key)
        }
    }

    /// Tries every known account (selected one first) until one can read the resource.
    static func get(_ path: String) async -> [String: Any]? {
        for account in accounts() {
            guard let pem = keychain(account.id), let token = jwt(account, pem: pem),
                  let url = URL(string: "https://api.appstoreconnect.apple.com" + path) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let result = try? await URLSession.shared.data(for: req),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] else { continue }
            return json
        }
        return nil
    }

    static func keychain(_ account: String) -> String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String else { return nil }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "nl.lrvdlinden.devtools",
                                kSecAttrAccount as String: account,
                                kSecAttrAccessGroup as String: prefix + "nl.lrvdlinden.devtools.shared",
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func jwt(_ account: Account, pem: String) -> String? {
        guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else { return nil }
        let now = Int(Date().timeIntervalSince1970)
        func b64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        guard let header = try? JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": account.key, "typ": "JWT"], options: [.sortedKeys]),
              let payload = try? JSONSerialization.data(withJSONObject: ["iss": account.issuer, "iat": now - 10, "exp": now + 600, "aud": "appstoreconnect-v1"], options: [.sortedKeys]) else { return nil }
        let signing = b64(header) + "." + b64(payload)
        guard let sig = try? key.signature(for: Data(signing.utf8)) else { return nil }
        return signing + "." + b64(sig.rawRepresentation)
    }
}

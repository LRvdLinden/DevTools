import Foundation
import CryptoKit
import Security

struct ConnectError: LocalizedError {
    let message: String
    var status: Int = 0
    var errorDescription: String? { message }
}

struct DeveloperAccount: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var issuerID: String
    var keyID: String
    /// Vendor number from "Payments and Financial Reports" — needed for Sales Reports (downloads, proceeds).
    var vendorNumber: String?

    var hasVendor: Bool { !(vendorNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Device-only Keychain storage for the .p8 private keys.
/// Items live in a shared access group so the push extension can read them to enrich notifications
/// (version, build and platform). Older items without a group are migrated on first read.
enum Vault {
    private static let service = "nl.lrvdlinden.devtools"

    /// "<TeamID>.nl.lrvdlinden.devtools.shared", from Info.plist (AppIdentifierPrefix is filled in by Xcode).
    static var sharedGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty, !prefix.contains("$") else { return nil }
        return prefix + "nl.lrvdlinden.devtools.shared"
    }

    private static func base(_ key: String, group: String?) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    static func save(_ value: String, key: String) throws {
        SecItemDelete(base(key, group: nil) as CFDictionary)
        var code = errSecMissingEntitlement
        if let group = sharedGroup {
            var add = base(key, group: group)
            add[kSecValueData as String] = Data(value.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            code = SecItemAdd(add as CFDictionary, nil)
        }
        if code != errSecSuccess {   // no shared group available (e.g. unsigned build): app-only item
            var add = base(key, group: nil)
            add[kSecValueData as String] = Data(value.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            code = SecItemAdd(add as CFDictionary, nil)
        }
        if code != errSecSuccess { throw ConnectError(message: L("Keychain-fout: \(code)")) }
    }

    private static func fetch(_ key: String, group: String?) -> String? {
        var q = base(key, group: group)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func read(_ key: String) -> String? {
        if let group = sharedGroup, let v = fetch(key, group: group) { return v }
        guard let legacy = fetch(key, group: nil) else { return nil }
        if sharedGroup != nil { try? save(legacy, key: key) }   // migrate into the shared group
        return legacy
    }

    static func delete(_ key: String) {
        SecItemDelete(base(key, group: nil) as CFDictionary)
        if let group = sharedGroup { SecItemDelete(base(key, group: group) as CFDictionary) }
    }
}

/// App Store Connect API client (https://developer.apple.com/documentation/appstoreconnectapi).
/// Authenticates with an ES256 JWT signed by the team API key.
struct ConnectAPI {
    let account: DeveloperAccount
    static let root = "https://api.appstoreconnect.apple.com"

    // MARK: Auth

    func token() throws -> String {
        guard let pem = Vault.read(account.id.uuidString) else { throw ConnectError(message: L("Privésleutel (.p8) ontbreekt voor dit account. Voeg het account opnieuw toe.")) }
        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(pemRepresentation: pem) }
        catch { throw ConnectError(message: L("Ongeldige ES256 .p8-sleutel: \(error.localizedDescription)")) }
        let now = Int(Date().timeIntervalSince1970)
        let header: [String: Any] = ["alg": "ES256", "kid": account.keyID, "typ": "JWT"]
        let payload: [String: Any] = ["iss": account.issuerID, "iat": now - 10, "exp": now + 1100, "aud": "appstoreconnect-v1"]
        let signing = try Self.b64(header) + "." + Self.b64(payload)
        let signature = try key.signature(for: Data(signing.utf8))
        return signing + "." + Self.b64url(signature.rawRepresentation)
    }

    private static func b64(_ obj: [String: Any]) throws -> String {
        b64url(try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]))
    }

    private static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: URL building

    private static let queryAllowed: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-._~,")
        return s
    }()

    func url(_ path: String, _ query: [(String, String)] = []) -> URL {
        if path.hasPrefix("http"), let u = URL(string: path) { return u }
        var s = Self.root + path
        if !query.isEmpty {
            let q = query.map { pair -> String in
                let k = pair.0.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? pair.0
                let v = pair.1.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? pair.1
                return k + "=" + v
            }.joined(separator: "&")
            s += "?" + q
        }
        return URL(string: s)!
    }

    // MARK: Requests

    @discardableResult
    func send(_ method: String, _ url: URL, body: Data? = nil, accept: String = "application/json") async throws -> (Data, Int) {
        if account.id == DemoData.accountID {
            try? await Task.sleep(for: .milliseconds(250))
            return (try DemoData.response(method: method, url: url), 200)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnectError(message: L("Geen HTTP-antwoord van Apple")) }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: data, status: http.statusCode)
        }
        return (data, http.statusCode)
    }

    static func error(from data: Data, status: Int) -> ConnectError {
        struct AppleErrors: Decodable {
            struct Item: Decodable { let code: String?; let title: String?; let detail: String? }
            let errors: [Item]?
        }
        var detail = ""
        if let parsed = try? JSONDecoder().decode(AppleErrors.self, from: data), let items = parsed.errors, !items.isEmpty {
            detail = items.map { item in
                let d = item.detail ?? item.title ?? item.code ?? ""
                return d
            }.joined(separator: "\n")
        } else {
            detail = String(decoding: data.prefix(400), as: UTF8.self)
        }
        let prefix: String
        switch status {
        case 401: prefix = L("Authenticatie mislukt (401). Controleer Issuer ID, Key ID en de .p8-sleutel.")
        case 403: prefix = L("Geen toegang (403). De API-sleutel heeft niet de juiste rol voor deze actie.")
        case 404: prefix = L("Niet gevonden (404).")
        case 409: prefix = L("Apple weigert deze wijziging (409).")
        case 429: prefix = L("Te veel verzoeken (429). Probeer het zo opnieuw.")
        default: prefix = L("Apple API-fout \(status).")
        }
        return ConnectError(message: detail.isEmpty ? prefix : prefix + "\n" + detail, status: status)
    }

    func get<T: Decodable>(_ path: String, _ query: [(String, String)] = [], as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await send("GET", url(path, query))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ConnectError(message: L("Antwoord van Apple kon niet gelezen worden: \(error.localizedDescription)"))
        }
    }

    /// Follows `links.next` and collects every page (bounded by `max`).
    func all<A: Decodable>(_ path: String, _ query: [(String, String)] = [], max: Int = 1000) async throws -> (data: [Resource<A>], included: [AnyResource]) {
        var next: URL? = url(path, query)
        var seen = Set<String>()
        var records: [Resource<A>] = []
        var included: [AnyResource] = []
        while let u = next, !seen.contains(u.absoluteString), records.count < max {
            seen.insert(u.absoluteString)
            let (data, _) = try await send("GET", u)
            let page: ListDocument<A>
            do { page = try JSONDecoder().decode(ListDocument<A>.self, from: data) }
            catch { throw ConnectError(message: L("Antwoord van Apple kon niet gelezen worden: \(error.localizedDescription)")) }
            records.append(contentsOf: page.data)
            included.append(contentsOf: page.included ?? [])
            next = page.links?.next.flatMap { URL(string: $0) }
        }
        return (records, included)
    }

    func write(_ method: String, _ path: String, _ body: [String: Any]?) async throws -> Data {
        let payload = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let (data, _) = try await send(method, url(path), body: payload)
        return data
    }

    /// POST that returns the created resource.
    func create<A: Decodable>(_ path: String, _ body: [String: Any], as type: A.Type) async throws -> Resource<A> {
        let data = try await write("POST", path, body)
        do { return try JSONDecoder().decode(SingleDocument<A>.self, from: data).data }
        catch { throw ConnectError(message: L("Aangemaakt, maar het antwoord kon niet gelezen worden.")) }
    }

    func patch(_ path: String, type: String, id: String, attributes: [String: Any]) async throws {
        let body: [String: Any] = ["data": ["type": type, "id": id, "attributes": attributes]]
        _ = try await write("PATCH", path, body)
    }

    // MARK: Reports (gzip)

    func report(_ path: String, _ query: [(String, String)]) async throws -> String {
        let (data, _) = try await send("GET", url(path, query), accept: "application/a-gzip")
        let raw = try Gzip.decompress(data)
        return String(decoding: raw, as: UTF8.self)
    }
}

// MARK: - JSON body helpers

enum Body {
    static func ref(_ type: String, _ id: String) -> [String: Any] { ["data": ["type": type, "id": id]] }
    static func refs(_ type: String, _ ids: [String]) -> [String: Any] { ["data": ids.map { ["type": type, "id": $0] }] }
}

// MARK: - Gzip

enum Gzip {
    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b else { return data }  // already plain text
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0, bytes.count > offset + 2 {
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { while offset < bytes.count && bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < bytes.count && bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { throw ConnectError(message: L("Ongeldig rapportbestand")) }
        let deflate = Data(bytes[offset..<(bytes.count - 8)])
        do {
            return try (deflate as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw ConnectError(message: L("Rapport kon niet uitgepakt worden: \(error.localizedDescription)"))
        }
    }
}

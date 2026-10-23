import Foundation
import CryptoKit
import Security
import WidgetKit

struct ConnectError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Vault {
    static func save(_ value: String, key: String) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"nl.lrvdlinden.devtools", kSecAttrAccount as String:key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let code = SecItemAdd(add as CFDictionary, nil)
        if code != errSecSuccess { throw ConnectError(message:"Keychain error: \(code)") }
    }
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"nl.lrvdlinden.devtools",kSecAttrAccount as String:key,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"nl.lrvdlinden.devtools",kSecAttrAccount as String:key]
        SecItemDelete(query as CFDictionary)
    }
}

enum ConnectAPI {
    static let root = URL(string:"https://api.appstoreconnect.apple.com")!
    static func jwt(account: DeveloperAccount) throws -> String {
        guard let pem = Vault.read(account.id.uuidString) else { throw ConnectError(message:"Private key missing") }
        let key: P256.Signing.PrivateKey
        do { key = try P256.Signing.PrivateKey(pemRepresentation:pem) }
        catch { throw ConnectError(message:"Invalid ES256 .p8 key: \(error.localizedDescription)") }
        let now = Int(Date().timeIntervalSince1970)
        let header: [String:Any] = ["alg":"ES256","kid":account.keyID,"typ":"JWT"]
        let payload: [String:Any] = ["iss":account.issuerID,"iat":now,"exp":now+900,"aud":"appstoreconnect-v1"]
        func b64(_ obj: [String:Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject:obj,options:[.sortedKeys])
            return data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
        }
        let signing = try b64(header) + "." + b64(payload)
        let signature = try key.signature(for:Data(signing.utf8))
        return signing + "." + signature.rawRepresentation.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
    static func get<T:Decodable>(_ path:String, account:DeveloperAccount, type:T.Type = T.self) async throws -> T {
        let url = URL(string:path,relativeTo:root)!.absoluteURL
        var request = URLRequest(url:url)
        request.setValue("Bearer \(try jwt(account:account))",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.timeoutInterval = 25
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse else { throw ConnectError(message:"No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding:data.prefix(800),as:UTF8.self)
            throw ConnectError(message:"Apple API HTTP \(http.statusCode): \(body)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self,from:data)
    }
    static func all<T:Decodable>(_ path:String, account:DeveloperAccount, type:T.Type) async throws -> [T] {
        var next: String? = path
        var seen = Set<String>()
        var records: [T] = []
        while let route=next, !seen.contains(route), records.count < 1000 {
            seen.insert(route)
            let page:APICollection<T> = try await get(route,account:account)
            records.append(contentsOf:page.data)
            next = page.links?.next?.absoluteString
        }
        return records
    }
}

@MainActor @Observable final class DevStore {
    var accounts: [DeveloperAccount] = []
    var selectedID: UUID?
    var apps: [AppSummary] = []
    var loading = false
    var error: String?
    var lastRefresh: Date?
    init() {
        if let data=UserDefaults.standard.data(forKey:"accounts"), let saved=try? JSONDecoder().decode([DeveloperAccount].self,from:data) { accounts=saved }
        if let raw=UserDefaults.standard.string(forKey:"selectedAccount") { selectedID=UUID(uuidString:raw) }
        if selectedID == nil { selectedID=accounts.first?.id }
    }
    var active: DeveloperAccount? { accounts.first { $0.id==selectedID } }
    func add(name:String,issuer:String,key:String,pem:String) throws {
        let item=DeveloperAccount(name:name,issuerID:issuer.trimmingCharacters(in:.whitespacesAndNewlines),keyID:key.trimmingCharacters(in:.whitespacesAndNewlines))
        guard !item.issuerID.isEmpty && !item.keyID.isEmpty && pem.contains("PRIVATE KEY") else { throw ConnectError(message:"Enter issuer ID, key ID and a valid .p8 file") }
        try Vault.save(pem,key:item.id.uuidString)
        accounts.append(item);selectedID=item.id;persist()
    }
    func remove(_ account:DeveloperAccount) {
        Vault.delete(account.id.uuidString);accounts.removeAll{$0.id==account.id}
        if selectedID==account.id {selectedID=accounts.first?.id;apps=[]};persist()
    }
    func select(_ account:DeveloperAccount) { selectedID=account.id;apps=[];persist();Task{await refresh()} }
    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts),forKey:"accounts")
        UserDefaults.standard.set(selectedID?.uuidString,forKey:"selectedAccount")
    }
    func refresh() async {
        guard let account=active else { return }
        loading=true;error=nil
        defer {loading=false}
        do {
            let items:[AppleResource<AppleAppAttributes>] = try await ConnectAPI.all("/v1/apps?limit=200",account:account,type:AppleResource<AppleAppAttributes>.self)
            var fresh=items.map { AppSummary(id:$0.id,name:$0.attributes.name,bundleID:$0.attributes.bundleId ?? "") }
            await withTaskGroup(of:(String,String,String,String).self) { group in
                for app in fresh {
                    group.addTask {
                        async let vers: APICollection<AppleResource<AppleVersionAttributes>> = ConnectAPI.get("/v1/apps/\(app.id)/appStoreVersions?limit=50",account:account)
                        async let builds: APICollection<AppleResource<AppleBuildAttributes>> = ConnectAPI.get("/v1/builds?filter[app]=\(app.id)&limit=50",account:account)
                        let v=try? await vers
                        let b=try? await builds
                        let latestVersion=v?.data.first
                        let latestBuild=b?.data.sorted { ($0.attributes.uploadedDate ?? .distantPast) > ($1.attributes.uploadedDate ?? .distantPast) }.first
                        return (app.id,latestVersion?.attributes.versionString ?? "—",latestVersion?.attributes.appStoreState ?? "—",latestBuild?.attributes.version ?? "—")
                    }
                }
                for await result in group {
                    if let i=fresh.firstIndex(where:{$0.id==result.0}) {
                        fresh[i].version=result.1;fresh[i].state=result.2;fresh[i].latestBuild=result.3
                    }
                }
            }
            guard active?.id==account.id else {return}
            apps=fresh.sorted{$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
            lastRefresh = .now
            SharedSnapshot(updated:.now,apps:apps.map{WidgetAppSummary(id:$0.id,name:$0.name,version:$0.version,state:$0.state)}).save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch { self.error=error.localizedDescription }
    }
    func versions(for id:String) async throws -> [AppleResource<AppleVersionAttributes>] {
        guard let active else{return []}
        return try await ConnectAPI.all("/v1/apps/\(id)/appStoreVersions?limit=200",account:active,type:AppleResource<AppleVersionAttributes>.self)
    }
    func builds(for id:String) async throws -> [AppleResource<AppleBuildAttributes>] {
        guard let active else{return []}
        return try await ConnectAPI.all("/v1/builds?filter[app]=\(id)&limit=200",account:active,type:AppleResource<AppleBuildAttributes>.self)
    }
    func reviews(for id:String) async throws -> [AppleResource<AppleReviewAttributes>] {
        guard let active else{return []}
        return try await ConnectAPI.all("/v1/apps/\(id)/customerReviews?limit=200",account:active,type:AppleResource<AppleReviewAttributes>.self)
    }
}

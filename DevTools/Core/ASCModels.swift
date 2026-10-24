import Foundation

// MARK: - JSON:API envelope (App Store Connect API)

struct Linkage: Codable, Hashable {
    let type: String
    let id: String
}

struct Relationship: Decodable {
    let one: Linkage?
    let many: [Linkage]

    private enum Keys: String, CodingKey { case data }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let single = try? c.decode(Linkage.self, forKey: .data) {
            one = single
            many = [single]
        } else if let list = try? c.decode([Linkage].self, forKey: .data) {
            one = list.first
            many = list
        } else {
            one = nil
            many = []
        }
    }
}

struct Resource<A: Decodable>: Decodable, Identifiable {
    let id: String
    let type: String
    let attributes: A
    let relationships: [String: Relationship]?

    func related(_ key: String) -> Linkage? { relationships?[key]?.one }
    func relatedAll(_ key: String) -> [Linkage] { relationships?[key]?.many ?? [] }
}

struct PageLinks: Decodable { let next: String? }
struct PagingMeta: Decodable { let paging: Paging? }
struct Paging: Decodable { let total: Int?; let limit: Int? }

struct ListDocument<A: Decodable>: Decodable {
    let data: [Resource<A>]
    let included: [AnyResource]?
    let links: PageLinks?
    let meta: PagingMeta?
}

struct SingleDocument<A: Decodable>: Decodable {
    let data: Resource<A>
    let included: [AnyResource]?
}

/// Optional single resource (e.g. GET /v1/customerReviews/{id}/response returns `data: null`).
struct OptionalDocument<A: Decodable>: Decodable {
    let data: Resource<A>?
}

/// A resource from `included` whose type isn't known up front.
struct AnyResource: Decodable {
    let id: String
    let type: String
    let attributes: JSONValue?

    func string(_ key: String) -> String? { attributes?[key]?.stringValue }
    func bool(_ key: String) -> Bool? { attributes?[key]?.boolValue }
}

enum JSONValue: Decodable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
}

extension Array where Element == AnyResource {
    func find(_ link: Linkage?) -> AnyResource? {
        guard let link else { return nil }
        return first { $0.type == link.type && $0.id == link.id }
    }
}

enum ASCDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return withFraction.date(from: s) ?? plain.date(from: s) ?? dayOnly.date(from: String(s.prefix(10)))
    }

    static func iso(_ d: Date) -> String { plain.string(from: d) }
}

// MARK: - Attributes

struct AppAttributes: Decodable {
    let name: String?
    let bundleId: String?
    let sku: String?
    let primaryLocale: String?
}

struct VersionAttributes: Decodable {
    let platform: String?
    let versionString: String?
    let appStoreState: String?
    let appVersionState: String?
    let createdDate: String?
    let releaseType: String?
    let earliestReleaseDate: String?
    let copyright: String?
    let downloadable: Bool?

    /// appStoreState reports READY_FOR_SALE only when the version is really live;
    /// appVersionState says READY_FOR_DISTRIBUTION for both live and "about to go live".
    var state: String { appStoreState ?? appVersionState ?? "" }
}

struct ImageAsset: Decodable, Hashable {
    let templateUrl: String?
    let width: Int?
    let height: Int?

    func url(size: Int = 256, format: String = "png") -> URL? {
        guard let t = templateUrl else { return nil }
        let s = t.replacingOccurrences(of: "{w}", with: "\(size)")
            .replacingOccurrences(of: "{h}", with: "\(size)")
            .replacingOccurrences(of: "{f}", with: format)
        return URL(string: s)
    }
}

struct BuildAttributes: Decodable {
    let version: String?
    let uploadedDate: String?
    let expirationDate: String?
    let expired: Bool?
    let minOsVersion: String?
    let processingState: String?
    let iconAssetToken: ImageAsset?
    let usesNonExemptEncryption: Bool?
    let buildAudienceType: String?
}

struct PreReleaseVersionAttributes: Decodable {
    let version: String?
    let platform: String?
}

struct BuildBetaDetailAttributes: Decodable {
    let autoNotifyEnabled: Bool?
    let internalBuildState: String?
    let externalBuildState: String?
}

struct BetaBuildLocalizationAttributes: Decodable {
    let whatsNew: String?
    let locale: String?
}

struct BetaGroupAttributes: Decodable {
    let name: String?
    let isInternalGroup: Bool?
    let publicLinkEnabled: Bool?
    let publicLink: String?
    let publicLinkLimit: Int?
    let publicLinkLimitEnabled: Bool?
    let createdDate: String?
    let hasAccessToAllBuilds: Bool?
}

struct BetaTesterAttributes: Decodable {
    let firstName: String?
    let lastName: String?
    let email: String?
    let inviteType: String?
    let state: String?

    var displayName: String {
        let n = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return n.isEmpty ? (email ?? L("Anonieme tester")) : n
    }
}

struct ReviewAttributes: Decodable {
    let rating: Int?
    let title: String?
    let body: String?
    let reviewerNickname: String?
    let createdDate: String?
    let territory: String?
}

struct ReviewResponseAttributes: Decodable {
    let responseBody: String?
    let lastModifiedDate: String?
    let state: String?
}

struct VersionLocalizationAttributes: Decodable {
    let locale: String?
    let description: String?
    let keywords: String?
    let marketingUrl: String?
    let promotionalText: String?
    let supportUrl: String?
    let whatsNew: String?
}

struct AppInfoAttributes: Decodable {
    let appStoreState: String?
    let state: String?
    var anyState: String { state ?? appStoreState ?? "" }
}

struct AppInfoLocalizationAttributes: Decodable {
    let locale: String?
    let name: String?
    let subtitle: String?
    let privacyPolicyUrl: String?
}

struct ReviewSubmissionAttributes: Decodable {
    let platform: String?
    let submittedDate: String?
    let state: String?
}

struct BetaAppReviewSubmissionAttributes: Decodable {
    let betaReviewState: String?
    let submittedDate: String?
}

struct EmptyAttributes: Decodable {}

// MARK: - App-level models used by the UI

struct VersionInfo: Identifiable, Hashable, Codable {
    let id: String
    var versionString: String
    var platform: String
    var state: String
    var created: Date?
    var releaseType: String
    var copyright: String
    var earliestRelease: Date?

    init(_ r: Resource<VersionAttributes>) {
        id = r.id
        versionString = r.attributes.versionString ?? "—"
        platform = r.attributes.platform ?? "IOS"
        state = r.attributes.state
        created = ASCDate.parse(r.attributes.createdDate)
        releaseType = r.attributes.releaseType ?? "AFTER_APPROVAL"
        copyright = r.attributes.copyright ?? ""
        earliestRelease = ASCDate.parse(r.attributes.earliestReleaseDate)
    }

    var isLive: Bool { AppState.isLive(state) }
    var isEditable: Bool { AppState.editableStates.contains(state) }
    var platformLabel: String { Platform.label(platform) }
}

struct BuildInfo: Identifiable, Hashable, Codable {
    let id: String
    var number: String
    var marketingVersion: String
    var platform: String
    var processingState: String
    var uploaded: Date?
    var expires: Date?
    var expired: Bool
    var minOS: String
    var iconURL: URL?
    var usesNonExemptEncryption: Bool?
    var internalState: String
    var externalState: String
    var betaDetailID: String?
    var autoNotify: Bool

    init(_ r: Resource<BuildAttributes>, included: [AnyResource]) {
        id = r.id
        number = r.attributes.version ?? "—"
        processingState = r.attributes.processingState ?? ""
        uploaded = ASCDate.parse(r.attributes.uploadedDate)
        expires = ASCDate.parse(r.attributes.expirationDate)
        expired = r.attributes.expired ?? false
        minOS = r.attributes.minOsVersion ?? ""
        iconURL = r.attributes.iconAssetToken?.url(size: 256)
        usesNonExemptEncryption = r.attributes.usesNonExemptEncryption
        let pre = included.find(r.related("preReleaseVersion"))
        marketingVersion = pre?.string("version") ?? ""
        platform = pre?.string("platform") ?? "IOS"
        let beta = included.find(r.related("buildBetaDetail"))
        betaDetailID = beta?.id ?? r.related("buildBetaDetail")?.id
        internalState = beta?.string("internalBuildState") ?? ""
        externalState = beta?.string("externalBuildState") ?? ""
        autoNotify = beta?.bool("autoNotifyEnabled") ?? true
    }

    var title: String { marketingVersion.isEmpty ? L("Build \(number)") : "\(marketingVersion) (\(number))" }
    var isUsable: Bool { processingState == "VALID" && !expired }
    var displayState: String {
        if expired { return "EXPIRED" }
        if processingState != "VALID" { return processingState }
        if !externalState.isEmpty && externalState != "READY_FOR_BETA_SUBMISSION" { return externalState }
        return internalState.isEmpty ? processingState : internalState
    }
    var needsCompliance: Bool { internalState == "MISSING_EXPORT_COMPLIANCE" || externalState == "MISSING_EXPORT_COMPLIANCE" }
}

enum Platform {
    static let all = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
    static func label(_ p: String) -> String {
        switch p {
        case "IOS": return "iOS"
        case "MAC_OS": return "macOS"
        case "TV_OS": return "tvOS"
        case "VISION_OS": return "visionOS"
        case "WATCH_OS": return "watchOS"
        default: return p
        }
    }
    static func icon(_ p: String) -> String {
        switch p {
        case "MAC_OS": return "macbook"
        case "TV_OS": return "appletv"
        case "VISION_OS": return "visionpro"
        default: return "iphone"
        }
    }
}

enum ReleaseType {
    static let all = ["AFTER_APPROVAL", "MANUAL", "SCHEDULED"]
    static func label(_ t: String) -> String {
        switch t {
        case "MANUAL": return L("Handmatig vrijgeven")
        case "SCHEDULED": return L("Op datum vrijgeven")
        default: return L("Automatisch na goedkeuring")
        }
    }
}

struct AppSummary: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var bundleID: String
    var sku: String
    var primaryLocale: String
    var versions: [VersionInfo] = []
    var latestBuild: BuildInfo?
    var artworkURL: URL?
    var rating: Double?
    var ratingCount: Int?
    var storeURL: URL?

    var iconURL: URL? { artworkURL ?? latestBuild?.iconURL }

    var liveVersion: VersionInfo? { versions.first { $0.isLive } }
    /// The newest version that is still being worked on (not live, not replaced).
    var pendingVersion: VersionInfo? {
        versions.first { !AppState.closedStates.contains($0.state) }
    }
    var isLive: Bool { liveVersion != nil }
    var inReview: Bool { versions.contains { AppState.isReview($0.state) } }
    var isRejected: Bool { versions.contains { ["REJECTED", "METADATA_REJECTED", "INVALID_BINARY"].contains($0.state) } }
    /// One headline status for lists: in-progress state wins, otherwise Live.
    var headlineState: String {
        if let p = pendingVersion { return p.state }
        if let l = liveVersion { return l.state }
        return versions.first?.state ?? ""
    }
    var platforms: [String] {
        var seen = Set<String>(), out: [String] = []
        for v in versions where seen.insert(v.platform).inserted { out.append(v.platform) }
        return out
    }
    var appStoreConnectURL: URL? { URL(string: "https://appstoreconnect.apple.com/apps/\(id)/distribution") }
    var publicStoreURL: URL? { storeURL ?? URL(string: "https://apps.apple.com/app/id\(id)") }
}

/// TestFlight usage of a build or (summed) an app: from /v1/builds/{id}/metrics/betaBuildUsages.
struct BetaUsage: Codable, Hashable {
    var installs = 0
    var sessions = 0
    var crashes = 0
    var feedback = 0
    var invites = 0
    /// Number of beta testers of the app (only on app totals).
    var testers: Int?

    static func + (a: BetaUsage, b: BetaUsage) -> BetaUsage {
        var r = BetaUsage(installs: a.installs + b.installs, sessions: a.sessions + b.sessions, crashes: a.crashes + b.crashes,
                          feedback: a.feedback + b.feedback, invites: a.invites + b.invites)
        if a.testers != nil || b.testers != nil { r.testers = (a.testers ?? 0) + (b.testers ?? 0) }
        return r
    }

    /// Sums every `values` object in an App Store Connect metrics response (one or more data points).
    static func parse(_ data: Data) -> BetaUsage {
        var u = BetaUsage()
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return u }
        func int(_ v: Any?) -> Int {
            if let n = v as? NSNumber { return n.intValue }
            if let s = v as? String, let d = Double(s) { return Int(d) }
            return 0
        }
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let values = dict["values"] as? [String: Any] {
                    u.installs += int(values["installCount"])
                    u.sessions += int(values["sessionCount"])
                    u.crashes += int(values["crashCount"])
                    u.feedback += int(values["feedbackCount"])
                    u.invites += int(values["inviteCount"])
                }
                for (k, v) in dict where k != "values" { walk(v) }
            } else if let list = node as? [Any] {
                list.forEach(walk)
            }
        }
        walk(json)
        return u
    }
}

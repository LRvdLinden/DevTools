import Foundation

struct APICollection<T: Decodable>: Decodable { let data: [T]; let links: PageLinks? }
struct PageLinks: Decodable { let next: URL? }
struct AppleResource<Attributes: Decodable>: Decodable, Identifiable {
    let id: String
    let type: String
    let attributes: Attributes
}
struct AppleAppAttributes: Decodable { let name: String; let bundleId: String?; let sku: String? }
struct AppleBuildAttributes: Decodable { let version: String?; let uploadedDate: Date?; let processingState: String?; let expired: Bool? }
struct AppleVersionAttributes: Decodable { let versionString: String?; let appStoreState: String?; let platform: String? }
struct AppleReviewAttributes: Decodable { let rating: Int?; let title: String?; let body: String?; let reviewerNickname: String?; let createdDate: Date?; let territory: String? }
struct DeveloperAccount: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var issuerID: String
    var keyID: String
}
struct AppSummary: Codable, Identifiable {
    let id: String
    var name: String
    var bundleID: String
    var version: String = "—"
    var state: String = "—"
    var latestBuild: String = "—"
    var reviewCount: Int = 0
}
struct WidgetAppSummary: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let state: String
}
struct SharedSnapshot: Codable {
    let updated: Date
    let apps: [WidgetAppSummary]
    var inReview: Int { apps.filter { $0.state.localizedCaseInsensitiveContains("REVIEW") }.count }
    static let placeholder = SharedSnapshot(updated: .now, apps: [])
    static let suite = "group.nl.lrvdlinden.devtools"
    static func load() -> SharedSnapshot {
        guard let d = UserDefaults(suiteName: suite)?.data(forKey: "snapshot"), let value = try? JSONDecoder().decode(Self.self, from: d) else { return .placeholder }
        return value
    }
    func save() { UserDefaults(suiteName: Self.suite)?.set(try? JSONEncoder().encode(self), forKey: "snapshot") }
}

import Foundation

/// Demo mode: realistic sample data without an API key. Used by App Review
/// ("Try the demo" on the welcome screen) and for the App Store screenshots
/// (launch argument `-demo`). Reads are answered locally; writes are refused.
enum DemoData {
    static let accountID = UUID(uuidString: "00000000-0000-4000-8000-00000000DE70")!
    static let account = DeveloperAccount(id: accountID, name: "PixelForges (demo)", issuerID: "demo", keyID: "DEMO000000", vendorNumber: "80000000")

    struct DemoApp {
        let id: String
        let name: String
        let bundle: String
        let sku: String
        let icon: String
        let rating: Double
        let ratings: Int
        let base: Double          // average daily downloads
        let price: Double         // proceeds per download (0 = free)
        let iap: Double           // proceeds per in-app purchase
        let versions: [(String, String, String, Int)]   // platform, version, state, days ago
        let build: String
        let marketing: String
    }

    static let apps: [DemoApp] = [
        DemoApp(id: "6740000001", name: "Bingr", bundle: "nl.lrvdlinden.bingr", sku: "BINGR", icon: "demo-bingr", rating: 4.8, ratings: 1284, base: 210, price: 0, iap: 4.24,
                versions: [("IOS", "1.1.0", "IN_REVIEW", 1), ("IOS", "1.0.0", "READY_FOR_SALE", 21), ("TV_OS", "1.0.0", "READY_FOR_SALE", 21)], build: "142", marketing: "1.1.0"),
        DemoApp(id: "6740000002", name: "Pitwall", bundle: "nl.lrvdlinden.pitwall", sku: "PITWALL", icon: "demo-pitwall", rating: 4.7, ratings: 532, base: 96, price: 0, iap: 0,
                versions: [("IOS", "1.2.0", "PENDING_DEVELOPER_RELEASE", 2), ("IOS", "1.1.0", "READY_FOR_SALE", 40)], build: "58", marketing: "1.2.0"),
        DemoApp(id: "6740000003", name: "Manga Vault", bundle: "nl.lrvdlinden.mangavault", sku: "MANGAVAULT", icon: "demo-manga", rating: 4.6, ratings: 318, base: 64, price: 1.69, iap: 0,
                versions: [("IOS", "1.3.0", "PREPARE_FOR_SUBMISSION", 3), ("IOS", "1.2.1", "READY_FOR_SALE", 33)], build: "37", marketing: "1.3.0"),
        DemoApp(id: "6740000004", name: "TVArt", bundle: "nl.lrvdlinden.tvart", sku: "TVART", icon: "demo-tvart", rating: 4.9, ratings: 147, base: 38, price: 0, iap: 0,
                versions: [("TV_OS", "2.0.0", "READY_FOR_DISTRIBUTION", 0), ("TV_OS", "1.4.0", "READY_FOR_SALE", 60)], build: "24", marketing: "2.0.0"),
        DemoApp(id: "6740000005", name: "HomeyDev", bundle: "nl.lrvdlinden.homeydev", sku: "HOMEYDEV", icon: "demo-homey", rating: 4.5, ratings: 96, base: 22, price: 0, iap: 0,
                versions: [("IOS", "1.4.0", "METADATA_REJECTED", 4), ("IOS", "1.3.7", "READY_FOR_SALE", 26)], build: "88", marketing: "1.4.0"),
        DemoApp(id: "6740000006", name: "World Radio", bundle: "nl.lrvdlinden.worldradio", sku: "WORLDRADIO", icon: "demo-radio", rating: 0, ratings: 0, base: 0, price: 0, iap: 0,
                versions: [("IOS", "1.0.0", "WAITING_FOR_REVIEW", 1)], build: "9", marketing: "1.0.0")
    ]

    static func iconURL(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "DemoIcons") }

    // MARK: Summaries for the store

    static func summaries() -> [AppSummary] {
        apps.map { a in
            var s = AppSummary(id: a.id, name: a.name, bundleID: a.bundle, sku: a.sku, primaryLocale: "en-US")
            s.versions = versionInfos(a)
            s.latestBuild = builds(a).first
            s.artworkURL = iconURL(a.icon)
            s.rating = a.ratings > 0 ? a.rating : nil
            s.ratingCount = a.ratings > 0 ? a.ratings : nil
            return s
        }
    }

    private static func ago(_ days: Int, hours: Int = 0) -> String {
        ASCDate.iso(Date().addingTimeInterval(-Double(days) * 86_400 - Double(hours) * 3_600))
    }

    private static func versionResources(_ a: DemoApp) -> [[String: Any]] {
        a.versions.enumerated().map { i, v in
            res("appStoreVersions", "\(a.id)-v\(i)", [
                "platform": v.0, "versionString": v.1, "appStoreState": v.2, "appVersionState": v.2,
                "createdDate": ago(v.3), "releaseType": "AFTER_APPROVAL", "copyright": "2026 PixelForges", "downloadable": true
            ])
        }
    }

    private static func versionInfos(_ a: DemoApp) -> [VersionInfo] {
        let doc: [String: Any] = ["data": versionResources(a)]
        guard let data = try? JSONSerialization.data(withJSONObject: doc),
              let list = try? JSONDecoder().decode(ListDocument<VersionAttributes>.self, from: data) else { return [] }
        return list.data.map { VersionInfo($0) }
    }

    private static func buildsDocument(_ a: DemoApp) -> [String: Any] {
        var data: [[String: Any]] = []
        var included: [[String: Any]] = []
        let states: [(String, String, Int)] = [("IN_BETA_TESTING", "IN_BETA_TESTING", 1), ("IN_BETA_TESTING", "BETA_APPROVED", 6), ("READY_FOR_BETA_TESTING", "READY_FOR_BETA_SUBMISSION", 12), ("EXPIRED", "EXPIRED", 95)]
        let number = Int(a.build) ?? 10
        for (i, st) in states.enumerated() {
            let id = "\(a.id)-b\(i)"
            let pre = "\(a.id)-pre\(i == 0 ? 0 : 1)"
            data.append(res("builds", id, [
                "version": "\(number - i * 3)", "uploadedDate": ago(st.2, hours: 3), "expirationDate": ago(st.2 - 90),
                "expired": i == 3, "minOsVersion": "17.0", "processingState": "VALID", "usesNonExemptEncryption": false,
                "buildAudienceType": "APP_STORE_ELIGIBLE"
            ], rels: ["preReleaseVersion": ["data": ["type": "preReleaseVersions", "id": pre]],
                      "buildBetaDetail": ["data": ["type": "buildBetaDetails", "id": id + "-d"]]]))
            included.append(res("buildBetaDetails", id + "-d", ["autoNotifyEnabled": true, "internalBuildState": st.0, "externalBuildState": st.1]))
        }
        included.append(res("preReleaseVersions", "\(a.id)-pre0", ["version": a.marketing, "platform": a.versions.first?.0 ?? "IOS"]))
        included.append(res("preReleaseVersions", "\(a.id)-pre1", ["version": a.versions.dropFirst().first?.1 ?? a.marketing, "platform": a.versions.first?.0 ?? "IOS"]))
        return ["data": data, "included": included]
    }

    private static func builds(_ a: DemoApp) -> [BuildInfo] {
        guard let data = try? JSONSerialization.data(withJSONObject: buildsDocument(a)),
              let doc = try? JSONDecoder().decode(ListDocument<BuildAttributes>.self, from: data) else { return [] }
        return doc.data.map { BuildInfo($0, included: doc.included ?? []) }
    }

    private static func res(_ type: String, _ id: String, _ attrs: [String: Any], rels: [String: Any]? = nil) -> [String: Any] {
        var r: [String: Any] = ["type": type, "id": id, "attributes": attrs]
        if let rels { r["relationships"] = rels }
        return r
    }

    // MARK: Local API

    static func response(method: String, url: URL) throws -> Data {
        guard method == "GET" else { throw ConnectError(message: L("Niet beschikbaar in de demo-modus"), status: 403) }
        let path = url.path
        let parts = path.split(separator: "/").map(String.init)   // ["v1", "apps", id, ...]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { query.first { $0.name == name }?.value }
        func app(_ id: String) -> DemoApp? { apps.first { id.hasPrefix($0.id) } }
        var doc: [String: Any] = ["data": [Any]()]

        switch true {
        case parts == ["v1", "apps"]:
            doc = ["data": apps.map { res("apps", $0.id, ["name": $0.name, "bundleId": $0.bundle, "sku": $0.sku, "primaryLocale": "en-US"]) }]
        case parts.count == 4 && parts[1] == "apps" && parts[3] == "appStoreVersions":
            doc = ["data": app(parts[2]).map(versionResources) ?? []]
        case parts.count == 3 && parts[1] == "appStoreVersions":
            if let a = app(parts[2]), let v = versionResources(a).first(where: { ($0["id"] as? String) == parts[2] }) { doc = ["data": v] }
        case parts.count == 4 && parts[1] == "appStoreVersions" && parts[3] == "appStoreVersionLocalizations":
            let a = app(parts[2])
            doc = ["data": [
                res("appStoreVersionLocalizations", parts[2] + "-en", [
                    "locale": "en-US",
                    "whatsNew": "• Brand-new home screen with live charts\n• Faster loading of your library\n• Fixes and performance improvements",
                    "promotionalText": "Now with live charts and widgets.",
                    "description": "\(a?.name ?? "This app") brings everything you love together in one beautiful app.",
                    "keywords": "streaming,player,library,widgets", "supportUrl": "https://pixelforges.nl/support", "marketingUrl": "https://pixelforges.nl"]),
                res("appStoreVersionLocalizations", parts[2] + "-nl", [
                    "locale": "nl-NL",
                    "whatsNew": "• Nieuw startscherm met live grafieken\n• Sneller laden\n• Verbeteringen",
                    "promotionalText": "Nu met live grafieken en widgets.",
                    "description": "\(a?.name ?? "Deze app") brengt alles samen in één mooie app.",
                    "keywords": "streaming,speler,bibliotheek", "supportUrl": "https://pixelforges.nl/support"])
            ]]
        case parts.count == 4 && parts[1] == "appStoreVersions" && parts[3] == "build":
            if let a = app(parts[2]), let b = (buildsDocument(a)["data"] as? [[String: Any]])?.first { doc = ["data": b] }
            else { doc = ["data": NSNull()] }
        case parts == ["v1", "builds"]:
            if let id = q("filter[app]"), let a = app(id) { doc = buildsDocument(a) }
        case parts.count == 3 && parts[1] == "builds":
            if let a = app(parts[2]) {
                let full = buildsDocument(a)
                if let b = (full["data"] as? [[String: Any]])?.first(where: { ($0["id"] as? String) == parts[2] }) {
                    doc = ["data": b, "included": full["included"] ?? []]
                }
            }
        case parts.count == 4 && parts[1] == "builds" && parts[3] == "betaBuildLocalizations":
            doc = ["data": [res("betaBuildLocalizations", parts[2] + "-l", ["locale": "en-US", "whatsNew": "Please test the new home screen, widgets and the Apple Watch app. Report anything odd via TestFlight feedback."])]]
        case parts.count == 4 && parts[1] == "apps" && parts[3] == "betaGroups":
            doc = ["data": groups(parts[2])]
        case parts == ["v1", "betaGroups"]:
            doc = ["data": q("filter[builds]").map { b in groups(b).filter { ($0["id"] as? String)?.hasSuffix("g0") == true || ($0["id"] as? String)?.hasSuffix("g1") == true } } ?? []]
        case parts.count == 4 && parts[1] == "betaGroups" && parts[3] == "betaTesters":
            let names = [("Sanne", "de Vries"), ("Mark", "Jansen"), ("Lotte", "Bakker"), ("Daan", "Visser"), ("Emma", "Smit"), ("Tim", "Mulder")]
            doc = ["data": names.enumerated().map { i, n in
                res("betaTesters", "\(parts[2])-t\(i)", ["firstName": n.0, "lastName": n.1, "email": "\(n.0.lowercased())@example.com", "inviteType": "EMAIL", "state": i == 5 ? "INVITED" : "INSTALLED"])
            }]
        case parts == ["v1", "betaAppReviewSubmissions"]:
            doc = ["data": [res("betaAppReviewSubmissions", "brs", ["betaReviewState": "APPROVED", "submittedDate": ago(5)])]]
        case parts.count == 4 && parts[1] == "apps" && parts[3] == "customerReviews":
            doc = reviews(parts[2])
        case parts.count == 4 && parts[1] == "apps" && parts[3] == "appInfos":
            doc = ["data": [res("appInfos", parts[2] + "-info", ["state": "PREPARE_FOR_SUBMISSION", "appStoreState": "PREPARE_FOR_SUBMISSION"])]]
        case parts.count == 4 && parts[1] == "appInfos" && parts[3] == "appInfoLocalizations":
            let a = app(parts[2])
            doc = ["data": [
                res("appInfoLocalizations", parts[2] + "-en", ["locale": "en-US", "name": a?.name ?? "App", "subtitle": "Your favourites, beautifully", "privacyPolicyUrl": "https://pixelforges.nl/privacy"]),
                res("appInfoLocalizations", parts[2] + "-nl", ["locale": "nl-NL", "name": a?.name ?? "App", "subtitle": "Je favorieten, prachtig", "privacyPolicyUrl": "https://pixelforges.nl/privacy"])
            ]]
        default:
            doc = ["data": [Any]()]
        }
        return try JSONSerialization.data(withJSONObject: doc)
    }

    private static func groups(_ appID: String) -> [[String: Any]] {
        let base = String(appID.prefix(10))
        return [
            res("betaGroups", base + "-g0", ["name": "Team PixelForges", "isInternalGroup": true, "hasAccessToAllBuilds": true, "createdDate": ago(200)]),
            res("betaGroups", base + "-g1", ["name": "Public beta", "isInternalGroup": false, "publicLinkEnabled": true, "publicLink": "https://testflight.apple.com/join/DEMO2026", "createdDate": ago(120)]),
            res("betaGroups", base + "-g2", ["name": "Friends & family", "isInternalGroup": false, "publicLinkEnabled": false, "createdDate": ago(90)])
        ]
    }

    private static func reviews(_ appID: String) -> [String: Any] {
        let items: [(Int, String, String, String, String, Int, String?)] = [
            (5, "Exactly what I needed", "Clean design, fast and the widgets are gorgeous. Easily the best app in its category.", "jvdberg", "NLD", 1, "Thank you so much! More widgets are on the way."),
            (5, "Love the Apple Watch app", "Checking things from my wrist is so handy. Keep it up!", "Sophie_R", "GBR", 3, nil),
            (4, "Great, one wish", "Works brilliantly. Would love an iPad landscape layout for the library.", "markdev", "USA", 5, "Great idea, it's on our roadmap for the next update."),
            (5, "Fantastisch", "Super snel en ziet er geweldig uit.", "lotte88", "NLD", 8, nil),
            (3, "Good but crashed once", "Crashed once while switching profiles; otherwise great.", "tvfan", "DEU", 12, nil),
            (5, "Five stars", "Simply the best. Thanks to the developer!", "Kees", "BEL", 17, nil)
        ]
        var data: [[String: Any]] = []
        var included: [[String: Any]] = []
        for (i, r) in items.enumerated() {
            let id = "\(appID)-r\(i)"
            var rels: [String: Any]? = nil
            if let reply = r.6 {
                included.append(res("customerReviewResponses", id + "-resp", ["responseBody": reply, "lastModifiedDate": ago(r.5 - 1), "state": "PUBLISHED"]))
                rels = ["response": ["data": ["type": "customerReviewResponses", "id": id + "-resp"]]]
            }
            data.append(res("customerReviews", id, ["rating": r.0, "title": r.1, "body": r.2, "reviewerNickname": r.3, "territory": r.4, "createdDate": ago(r.5)], rels: rels))
        }
        return ["data": data, "included": included]
    }

    // MARK: Sales

    private static func noise(_ seed: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 97)
        x ^= x >> 13; x = x &* 0x5bd1e995; x ^= x >> 15
        return Double(x % 1000) / 1000.0
    }

    static func salesRows(for date: Date, weekly: Bool) -> [SalesRow] {
        let dayIndex = Int(date.timeIntervalSince1970 / 86_400)
        let days = weekly ? 7 : 1
        let countries: [(String, Double)] = [("US", 0.31), ("NL", 0.18), ("GB", 0.12), ("DE", 0.11), ("CA", 0.06), ("BE", 0.05), ("FR", 0.05), ("AU", 0.04), ("JP", 0.04), ("SE", 0.04)]
        var rows: [SalesRow] = []
        for (ai, a) in apps.enumerated() where a.base > 0 {
            let trend = 1.0 + 0.004 * Double(dayIndex % 365)
            let weekday = Calendar.current.component(.weekday, from: date)
            let weekend = (weekday == 1 || weekday == 7) ? 1.25 : 1.0
            let wave = 1 + 0.18 * sin(Double(dayIndex) / 4.5 + Double(ai))
            let total = a.base * trend * weekend * wave * (0.85 + 0.3 * noise(dayIndex * 31 + ai)) * Double(days) / 1.6
            for (ci, c) in countries.enumerated() {
                let n = Int((total * c.1 * (0.8 + 0.4 * noise(dayIndex * 7 + ci + ai * 13))).rounded())
                guard n > 0 else { continue }
                let device = ci % 4 == 0 ? "iPad" : (a.versions.first?.0 == "TV_OS" ? "Apple TV" : "iPhone")
                let currency = c.0 == "US" ? "USD" : (c.0 == "GB" ? "GBP" : (["CA", "AU", "JP", "SE"].contains(c.0) ? "USD" : "EUR"))
                let proceeds = a.price
                rows.append(SalesRow(appleID: a.id, parentID: "", sku: a.sku, title: a.name, type: "1F", units: n, proceeds: proceeds, currency: "EUR", country: c.0, device: device))
                let re = Int(Double(n) * 0.22)
                if re > 0 { rows.append(SalesRow(appleID: a.id, parentID: "", sku: a.sku, title: a.name, type: "3F", units: re, proceeds: 0, currency: "EUR", country: c.0, device: device)) }
                let up = Int(Double(n) * 2.4)
                if up > 0 { rows.append(SalesRow(appleID: a.id, parentID: "", sku: a.sku, title: a.name, type: "7F", units: up, proceeds: 0, currency: currency, country: c.0, device: device)) }
                if a.iap > 0 {
                    let iapUnits = Int(Double(n) * 0.09)
                    if iapUnits > 0 { rows.append(SalesRow(appleID: a.id + "01", parentID: a.sku, sku: a.sku + "_LIFETIME", title: "Lifetime", type: "IA1", units: iapUnits, proceeds: a.iap, currency: "EUR", country: c.0, device: device)) }
                }
            }
        }
        return rows
    }
}

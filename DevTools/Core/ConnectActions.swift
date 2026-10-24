import Foundation

/// Read/write operations on App Store Connect used by the screens.
extension ConnectAPI {

    // MARK: - App Store versions

    func versions(appID: String) async throws -> [VersionInfo] {
        let r: (data: [Resource<VersionAttributes>], included: [AnyResource]) = try await all("/v1/apps/\(appID)/appStoreVersions", [("limit", "50")], max: 200)
        return r.data.map { VersionInfo($0) }.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }

    func version(_ id: String) async throws -> VersionInfo {
        let doc: SingleDocument<VersionAttributes> = try await get("/v1/appStoreVersions/\(id)")
        return VersionInfo(doc.data)
    }

    func createVersion(appID: String, platform: String, versionString: String, releaseType: String) async throws -> VersionInfo {
        let body: [String: Any] = ["data": [
            "type": "appStoreVersions",
            "attributes": ["platform": platform, "versionString": versionString, "releaseType": releaseType],
            "relationships": ["app": Body.ref("apps", appID)]
        ]]
        let created = try await create("/v1/appStoreVersions", body, as: VersionAttributes.self)
        return VersionInfo(created)
    }

    func updateVersion(_ id: String, attributes: [String: Any]) async throws {
        try await patch("/v1/appStoreVersions/\(id)", type: "appStoreVersions", id: id, attributes: attributes)
    }

    func deleteVersion(_ id: String) async throws {
        _ = try await write("DELETE", "/v1/appStoreVersions/\(id)", nil)
    }

    func versionLocalizations(versionID: String) async throws -> [Resource<VersionLocalizationAttributes>] {
        let r: (data: [Resource<VersionLocalizationAttributes>], included: [AnyResource]) = try await all("/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations", [("limit", "50")])
        return r.data.sorted { ($0.attributes.locale ?? "") < ($1.attributes.locale ?? "") }
    }

    func updateVersionLocalization(_ id: String, attributes: [String: Any]) async throws {
        try await patch("/v1/appStoreVersionLocalizations/\(id)", type: "appStoreVersionLocalizations", id: id, attributes: attributes)
    }

    func createVersionLocalization(versionID: String, locale: String, attributes: [String: Any]) async throws {
        var attrs = attributes
        attrs["locale"] = locale
        let body: [String: Any] = ["data": [
            "type": "appStoreVersionLocalizations",
            "attributes": attrs,
            "relationships": ["appStoreVersion": Body.ref("appStoreVersions", versionID)]
        ]]
        _ = try await write("POST", "/v1/appStoreVersionLocalizations", body)
    }

    func versionBuild(versionID: String) async throws -> BuildInfo? {
        let doc: OptionalDocument<BuildAttributes> = try await get("/v1/appStoreVersions/\(versionID)/build")
        return doc.data.map { BuildInfo($0, included: []) }
    }

    func setVersionBuild(versionID: String, buildID: String) async throws {
        _ = try await write("PATCH", "/v1/appStoreVersions/\(versionID)/relationships/build", Body.ref("builds", buildID))
    }

    /// Creates (or reuses) a review submission, adds the version and submits it to App Review.
    func submitForReview(appID: String, versionID: String, platform: String) async throws {
        let open: ListDocument<ReviewSubmissionAttributes> = try await get("/v1/reviewSubmissions", [
            ("filter[app]", appID),
            ("filter[platform]", platform),
            ("filter[state]", "READY_FOR_REVIEW,UNRESOLVED_ISSUES")
        ])
        let submissionID: String
        if let existing = open.data.first {
            submissionID = existing.id
        } else {
            let body: [String: Any] = ["data": [
                "type": "reviewSubmissions",
                "attributes": ["platform": platform],
                "relationships": ["app": Body.ref("apps", appID)]
            ]]
            submissionID = try await create("/v1/reviewSubmissions", body, as: ReviewSubmissionAttributes.self).id
        }
        let item: [String: Any] = ["data": [
            "type": "reviewSubmissionItems",
            "relationships": [
                "reviewSubmission": Body.ref("reviewSubmissions", submissionID),
                "appStoreVersion": Body.ref("appStoreVersions", versionID)
            ]
        ]]
        do {
            _ = try await write("POST", "/v1/reviewSubmissionItems", item)
        } catch let e as ConnectError where e.status == 409 {
            // Already part of this submission — continue with submitting.
            if !e.message.localizedCaseInsensitiveContains("already") { throw e }
        }
        try await patch("/v1/reviewSubmissions/\(submissionID)", type: "reviewSubmissions", id: submissionID, attributes: ["submitted": true])
    }

    /// Cancels the active App Review submission(s) of an app.
    func cancelReview(appID: String, platform: String) async throws {
        let active: ListDocument<ReviewSubmissionAttributes> = try await get("/v1/reviewSubmissions", [
            ("filter[app]", appID),
            ("filter[platform]", platform),
            ("filter[state]", "WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES,READY_FOR_REVIEW")
        ])
        guard !active.data.isEmpty else { throw ConnectError(message: L("Geen actieve review-inzending gevonden.")) }
        for sub in active.data {
            try await patch("/v1/reviewSubmissions/\(sub.id)", type: "reviewSubmissions", id: sub.id, attributes: ["canceled": true])
        }
    }

    /// Releases a version that is "Pending Developer Release".
    func releaseVersion(versionID: String) async throws {
        let body: [String: Any] = ["data": [
            "type": "appStoreVersionReleaseRequests",
            "relationships": ["appStoreVersion": Body.ref("appStoreVersions", versionID)]
        ]]
        _ = try await write("POST", "/v1/appStoreVersionReleaseRequests", body)
    }

    // MARK: - App info (name, subtitle)

    func editableAppInfo(appID: String) async throws -> (id: String, state: String)? {
        let doc: ListDocument<AppInfoAttributes> = try await get("/v1/apps/\(appID)/appInfos")
        let infos = doc.data
        let editable = infos.first { !["READY_FOR_SALE", "REPLACED_WITH_NEW_INFO"].contains($0.attributes.anyState) } ?? infos.first
        return editable.map { ($0.id, $0.attributes.anyState) }
    }

    func appInfoLocalizations(infoID: String) async throws -> [Resource<AppInfoLocalizationAttributes>] {
        let r: (data: [Resource<AppInfoLocalizationAttributes>], included: [AnyResource]) = try await all("/v1/appInfos/\(infoID)/appInfoLocalizations", [("limit", "50")])
        return r.data.sorted { ($0.attributes.locale ?? "") < ($1.attributes.locale ?? "") }
    }

    func updateAppInfoLocalization(_ id: String, attributes: [String: Any]) async throws {
        try await patch("/v1/appInfoLocalizations/\(id)", type: "appInfoLocalizations", id: id, attributes: attributes)
    }

    // MARK: - Builds / TestFlight

    func builds(appID: String, limit: Int = 60) async throws -> [BuildInfo] {
        let doc: ListDocument<BuildAttributes> = try await get("/v1/builds", [
            ("filter[app]", appID),
            ("sort", "-uploadedDate"),
            ("limit", "\(min(limit, 200))"),
            ("include", "preReleaseVersion,buildBetaDetail")
        ])
        let included = doc.included ?? []
        return doc.data.map { BuildInfo($0, included: included) }
    }

    func build(_ id: String) async throws -> BuildInfo {
        let doc: SingleDocument<BuildAttributes> = try await get("/v1/builds/\(id)", [("include", "preReleaseVersion,buildBetaDetail")])
        return BuildInfo(doc.data, included: doc.included ?? [])
    }

    func expireBuild(_ id: String) async throws {
        try await patch("/v1/builds/\(id)", type: "builds", id: id, attributes: ["expired": true])
    }

    func setEncryption(buildID: String, usesNonExempt: Bool) async throws {
        try await patch("/v1/builds/\(buildID)", type: "builds", id: buildID, attributes: ["usesNonExemptEncryption": usesNonExempt])
    }

    func setAutoNotify(detailID: String, enabled: Bool) async throws {
        try await patch("/v1/buildBetaDetails/\(detailID)", type: "buildBetaDetails", id: detailID, attributes: ["autoNotifyEnabled": enabled])
    }

    func betaLocalizations(buildID: String) async throws -> [Resource<BetaBuildLocalizationAttributes>] {
        let doc: ListDocument<BetaBuildLocalizationAttributes> = try await get("/v1/builds/\(buildID)/betaBuildLocalizations", [("limit", "50")])
        return doc.data
    }

    func saveWhatToTest(buildID: String, localizationID: String?, locale: String, text: String) async throws {
        if let localizationID {
            try await patch("/v1/betaBuildLocalizations/\(localizationID)", type: "betaBuildLocalizations", id: localizationID, attributes: ["whatsNew": text])
        } else {
            let body: [String: Any] = ["data": [
                "type": "betaBuildLocalizations",
                "attributes": ["locale": locale, "whatsNew": text],
                "relationships": ["build": Body.ref("builds", buildID)]
            ]]
            _ = try await write("POST", "/v1/betaBuildLocalizations", body)
        }
    }

    func betaGroups(appID: String) async throws -> [Resource<BetaGroupAttributes>] {
        let doc: ListDocument<BetaGroupAttributes> = try await get("/v1/apps/\(appID)/betaGroups", [("limit", "100")])
        return doc.data.sorted { ($0.attributes.isInternalGroup ?? false) && !($1.attributes.isInternalGroup ?? false) }
    }

    func groupIDs(forBuild buildID: String) async throws -> Set<String> {
        let doc: ListDocument<BetaGroupAttributes> = try await get("/v1/betaGroups", [("filter[builds]", buildID), ("limit", "100")])
        return Set(doc.data.map(\.id))
    }

    func addBuild(_ buildID: String, toGroup groupID: String) async throws {
        _ = try await write("POST", "/v1/betaGroups/\(groupID)/relationships/builds", Body.refs("builds", [buildID]))
    }

    func removeBuild(_ buildID: String, fromGroup groupID: String) async throws {
        _ = try await write("DELETE", "/v1/betaGroups/\(groupID)/relationships/builds", Body.refs("builds", [buildID]))
    }

    func betaReviewState(buildID: String) async throws -> String? {
        let doc: ListDocument<BetaAppReviewSubmissionAttributes> = try await get("/v1/betaAppReviewSubmissions", [("filter[build]", buildID)])
        return doc.data.first?.attributes.betaReviewState
    }

    func submitForBetaReview(buildID: String) async throws {
        let body: [String: Any] = ["data": [
            "type": "betaAppReviewSubmissions",
            "relationships": ["build": Body.ref("builds", buildID)]
        ]]
        _ = try await write("POST", "/v1/betaAppReviewSubmissions", body)
    }

    func createBetaGroup(appID: String, name: String, isInternal: Bool) async throws {
        var attrs: [String: Any] = ["name": name]
        if isInternal { attrs["isInternalGroup"] = true; attrs["hasAccessToAllBuilds"] = true }
        let body: [String: Any] = ["data": [
            "type": "betaGroups",
            "attributes": attrs,
            "relationships": ["app": Body.ref("apps", appID)]
        ]]
        _ = try await write("POST", "/v1/betaGroups", body)
    }

    func deleteBetaGroup(_ id: String) async throws {
        _ = try await write("DELETE", "/v1/betaGroups/\(id)", nil)
    }

    func setPublicLink(groupID: String, enabled: Bool) async throws {
        try await patch("/v1/betaGroups/\(groupID)", type: "betaGroups", id: groupID, attributes: ["publicLinkEnabled": enabled])
    }

    func testers(groupID: String) async throws -> [Resource<BetaTesterAttributes>] {
        let r: (data: [Resource<BetaTesterAttributes>], included: [AnyResource]) = try await all("/v1/betaGroups/\(groupID)/betaTesters", [("limit", "200")], max: 2000)
        return r.data
    }

    func addTester(groupID: String, email: String, firstName: String, lastName: String) async throws {
        var attrs: [String: Any] = ["email": email]
        if !firstName.isEmpty { attrs["firstName"] = firstName }
        if !lastName.isEmpty { attrs["lastName"] = lastName }
        let body: [String: Any] = ["data": [
            "type": "betaTesters",
            "attributes": attrs,
            "relationships": ["betaGroups": Body.refs("betaGroups", [groupID])]
        ]]
        _ = try await write("POST", "/v1/betaTesters", body)
    }

    func removeTester(_ testerID: String, fromGroup groupID: String) async throws {
        _ = try await write("DELETE", "/v1/betaGroups/\(groupID)/relationships/betaTesters", Body.refs("betaTesters", [testerID]))
    }

    // MARK: - Customer reviews

    struct ReviewItem: Identifiable {
        let id: String
        let rating: Int
        let title: String
        let body: String
        let nickname: String
        let date: Date?
        let territory: String
        var responseID: String?
        var response: String?
        var responseState: String?
    }

    func reviews(appID: String, max: Int = 400) async throws -> [ReviewItem] {
        let r: (data: [Resource<ReviewAttributes>], included: [AnyResource]) = try await all("/v1/apps/\(appID)/customerReviews", [
            ("sort", "-createdDate"),
            ("limit", "200"),
            ("include", "response")
        ], max: max)
        return r.data.map { rev in
            let resp = r.included.find(rev.related("response"))
            return ReviewItem(id: rev.id, rating: rev.attributes.rating ?? 0, title: rev.attributes.title ?? "",
                              body: rev.attributes.body ?? "", nickname: rev.attributes.reviewerNickname ?? "",
                              date: ASCDate.parse(rev.attributes.createdDate), territory: rev.attributes.territory ?? "",
                              responseID: resp?.id, response: resp?.string("responseBody"), responseState: resp?.string("state"))
        }
    }

    func respond(toReview reviewID: String, text: String) async throws {
        let body: [String: Any] = ["data": [
            "type": "customerReviewResponses",
            "attributes": ["responseBody": text],
            "relationships": ["review": Body.ref("customerReviews", reviewID)]
        ]]
        _ = try await write("POST", "/v1/customerReviewResponses", body)
    }

    func deleteResponse(_ id: String) async throws {
        _ = try await write("DELETE", "/v1/customerReviewResponses/\(id)", nil)
    }
}

// MARK: - TestFlight usage

extension ConnectAPI {
    /// Installs, sessions, crashes, feedback and invites of one build.
    func betaUsage(buildID: String) async throws -> BetaUsage {
        // Apple accepts no query parameters here (limit only works together with groupBy/filter).
        let (data, _) = try await send("GET", url("/v1/builds/\(buildID)/metrics/betaBuildUsages"))
        return BetaUsage.parse(data)
    }

    /// Total number of beta testers of an app (meta.paging.total).
    func betaTesterCount(appID: String) async throws -> Int {
        let (data, _) = try await send("GET", url("/v1/betaTesters", [("filter[apps]", appID), ("limit", "1"), ("fields[betaTesters]", "state")]))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        if let meta = json["meta"] as? [String: Any], let paging = meta["paging"] as? [String: Any], let total = paging["total"] as? NSNumber {
            return total.intValue
        }
        return (json["data"] as? [Any])?.count ?? 0
    }
}

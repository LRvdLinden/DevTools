import SwiftUI

/// Opens the screen a tapped push notification is about: version, build, TestFlight feedback or the app.
struct PushRouteView: View {
    let route: PushRoute
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target: Target?
    @State private var error: String?

    enum Target {
        case version(appID: String, version: VersionInfo)
        case build(app: AppSummary, buildID: String)
        case feedback(item: JRes, isCrash: Bool, build: BuildInfo?)
        case app(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch target {
                case .version(let appID, let version)?: VersionDetailView(appID: appID, version: version)
                case .build(let app, let buildID)?: BuildDetailView(app: app, buildID: buildID)
                case .feedback(let item, let isCrash, let build)?: FeedbackDetailView(item: item, isCrash: isCrash, build: build) {}
                case .app(let id)?: AppDetailView(appID: id)
                case nil:
                    if let error {
                        ContentUnavailableView("Kon de melding niet openen", systemImage: "bell.slash", description: Text(error))
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } } }
        }
        .task { await resolve() }
    }

    private func app(_ id: String) async -> AppSummary? {
        if let a = store.apps.first(where: { $0.id == id }) { return a }
        await store.refresh()
        return store.apps.first { $0.id == id }
    }

    private func resolve() async {
        guard let api = store.api else { error = L("Geen account geselecteerd"); return }
        do {
            switch route.event {
            case "appStoreVersionAppVersionStateUpdated":
                let doc = try await api.jget("/v1/appStoreVersions/\(route.instanceID)", [("include", "app")])
                guard let appID = doc.data.first?.rel("app") ?? (route.appID.isEmpty ? nil : route.appID) else { break }
                await store.reloadApp(appID)
                if let v = (await app(appID))?.versions.first(where: { $0.id == route.instanceID }) {
                    target = .version(appID: appID, version: v); return
                }
                target = .app(appID); return
            case "buildUploadStateUpdated", "buildBetaDetailExternalBuildStateUpdated":
                var buildID = route.instanceID
                if route.event == "buildBetaDetailExternalBuildStateUpdated" {
                    buildID = try await api.jget("/v1/buildBetaDetails/\(route.instanceID)/build").data.first?.id ?? buildID
                }
                let doc = try await api.jget("/v1/builds/\(buildID)", [("include", "app")])
                let appID = doc.data.first?.rel("app") ?? route.appID
                if let a = await app(appID) { target = .build(app: a, buildID: buildID); return }
            case "betaFeedbackScreenshotSubmissionCreated", "betaFeedbackCrashSubmissionCreated":
                let crash = route.event == "betaFeedbackCrashSubmissionCreated"
                let path = crash ? "/v1/betaFeedbackCrashSubmissions/" : "/v1/betaFeedbackScreenshotSubmissions/"
                if let item = try await api.jget(path + route.instanceID).data.first {
                    var build: BuildInfo?
                    if let bid = item.rel("build") { build = try? await api.build(bid) }
                    target = .feedback(item: item, isCrash: crash, build: build); return
                }
            default:
                break
            }
            if !route.appID.isEmpty { target = .app(route.appID) } else { error = L("Deze melding hoort niet bij een scherm in DevTools.") }
        } catch {
            if !route.appID.isEmpty { target = .app(route.appID) } else { self.error = error.localizedDescription }
        }
    }
}

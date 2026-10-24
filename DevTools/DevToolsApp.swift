import SwiftUI
import UIKit
#if !targetEnvironment(macCatalyst)
import WatchConnectivity
#endif

@main
struct DevToolsApp: App {
    @State private var store = DevStore()
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system
    @AppStorage(LanguageManager.key, store: LanguageManager.defaults) private var language = ""

    init() {
        LanguageManager.apply()
        PushManager.initialize()
        PhoneWatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.locale, LanguageManager.locale)
                .id(language)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                #if targetEnvironment(macCatalyst)
                .frame(minWidth: 900, minHeight: 620)
                #endif
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Vernieuwen") {
                    Task { await store.refresh(); await store.refreshBetaUsage(force: true) }
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Downloadrapporten opnieuw ophalen") {
                    Task { await store.refreshSales(force: true) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

struct RootView: View {
    @Environment(DevStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = !LaunchArgs.noSplash
    @State private var splashFinished = 0

    var body: some View {
        ZStack {
            Group {
                if store.active == nil {
                    WelcomeView()
                } else {
                    MainView()
                        .id(store.selectedID)
                }
            }
            .animation(.default, value: store.active == nil)

            if showSplash {
                SplashView(progress: store.active == nil ? 1 : store.progress,
                           phase: store.active == nil ? "Welkom" : store.phase)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 1.2))))
                    .zIndex(10)
            }
        }
        .sensoryFeedback(.success, trigger: splashFinished)
        .task { await runSplash() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !showSplash, store.active != nil else { return }
            if let last = store.lastRefresh, Date().timeIntervalSince(last) < 600 { return }
            Task { await store.refresh() }
        }
    }

    private func runSplash() async {
        if LaunchArgs.demo && !store.isDemo { store.startDemo() }
        if LaunchArgs.noSplash {
            showSplash = false
            return
        }
        let start = Date()
        let hasCache = !store.apps.isEmpty
        if store.active != nil {
            Task { await store.refresh() }
        }
        if LaunchArgs.args.contains("-holdSplash") { return }
        let minimum = 2.4
        let maximum = store.active == nil ? 2.4 : (hasCache ? 4.0 : 7.0)
        while true {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= maximum { break }
            if elapsed >= minimum && !store.loading { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        withAnimation(.easeInOut(duration: 0.55)) { showSplash = false }
        splashFinished += 1
    }
}

/// Launch arguments used for demo mode and the App Store screenshots
/// (e.g. `-demo -noSplash -screen insights`).
enum LaunchArgs {
    static let args = ProcessInfo.processInfo.arguments
    static var demo: Bool { args.contains("-demo") }
    static var noSplash: Bool { args.contains("-noSplash") }
    static var screen: String? {
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

enum ScreenRoute: Hashable {
    case app(String)
    case version(String, VersionInfo)
    case reviews(String)
    case builds(String)
    case build(String, String)
    case guide
}

struct RouteDestination: View {
    let route: ScreenRoute
    @Environment(DevStore.self) private var store

    var body: some View {
        switch route {
        case .app(let id): AppDetailView(appID: id)
        case .version(let id, let v): VersionDetailView(appID: id, version: v)
        case .reviews(let id):
            if let app = store.apps.first(where: { $0.id == id }) { ReviewsView(app: app) }
        case .builds(let id):
            if let app = store.apps.first(where: { $0.id == id }) { AppBuildsView(app: app) }
        case .build(let id, let buildID):
            if let app = store.apps.first(where: { $0.id == id }) { BuildDetailView(app: app, buildID: buildID) }
        case .guide: GuideView()
        }
    }
}

/// Initial tab + pushed screens for a `-screen` launch argument.
enum ScreenPlan {
    static func tab(_ screen: String?) -> Int {
        switch screen {
        case "apps", "app", "version", "reviews": return 1
        case "testflight", "build": return 2
        case "insights": return 3
        case "account", "guide": return 4
        default: return 0
        }
    }

    @MainActor
    static func path(_ screen: String?, apps: [AppSummary]) -> [ScreenRoute] {
        guard let first = apps.first else { return [] }
        switch screen {
        case "app": return [.app(first.id)]
        case "version":
            let target = apps.first { $0.pendingVersion?.state == "PREPARE_FOR_SUBMISSION" } ?? first
            guard let v = target.pendingVersion ?? target.versions.first else { return [.app(target.id)] }
            return [.app(target.id), .version(target.id, v)]
        case "reviews": return [.app(first.id), .reviews(first.id)]
        case "build":
            guard let b = first.latestBuild else { return [.builds(first.id)] }
            return [.builds(first.id), .build(first.id, b.id)]
        case "guide": return [.guide]
        default: return []
        }
    }
}

/// iPhone: tab bar. iPad: sidebar.
struct MainView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(DevStore.self) private var store
    @State private var tab = ScreenPlan.tab(LaunchArgs.screen)
    @State private var paths: [[ScreenRoute]] = Array(repeating: [], count: 5)

    var body: some View {
        if sizeClass == .regular {
            SidebarRootView()
        } else {
            TabView(selection: $tab) {
                stack(0) { DashboardView() }
                    .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
                stack(1) { AppsListView() }
                    .tabItem { Label("Apps", systemImage: "square.stack.3d.up.fill") }.tag(1)
                stack(2) { TestFlightView() }
                    .tabItem { Label("TestFlight", systemImage: "airplane") }.tag(2)
                stack(3) { InsightsView() }
                    .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }.tag(3)
                stack(4) { AccountView() }
                    .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }.tag(4)
            }
            .onAppear {
                if LaunchArgs.screen != nil {
                    paths[tab] = ScreenPlan.path(LaunchArgs.screen, apps: store.apps)
                }
            }
        }
    }

    private func stack<Content: View>(_ index: Int, @ViewBuilder _ root: () -> Content) -> some View {
        NavigationStack(path: $paths[index]) {
            root().navigationDestination(for: ScreenRoute.self) { RouteDestination(route: $0) }
        }
    }
}

enum SidebarItem: Hashable {
    case home, apps, testflight, insights, account
    case app(String)
}

struct SidebarRootView: View {
    @Environment(DevStore.self) private var store
    @State private var selection: SidebarItem? = {
        switch LaunchArgs.screen {
        case "apps": return .apps
        case "testflight", "build": return .testflight
        case "insights": return .insights
        case "account", "guide": return .account
        default: return .home
        }
    }()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    HStack(spacing: 10) {
                        Image("SplashLogo").resizable().scaledToFit().frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("DevTools").font(.title3.weight(.bold))
                            Text(store.active?.name ?? "").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Label("Home", systemImage: "house.fill").tag(SidebarItem.home)
                    Label("Apps", systemImage: "square.stack.3d.up.fill").tag(SidebarItem.apps)
                    Label("TestFlight", systemImage: "airplane").tag(SidebarItem.testflight)
                    Label("Insights", systemImage: "chart.xyaxis.line").tag(SidebarItem.insights)
                    Label("Account", systemImage: "person.crop.circle.fill").tag(SidebarItem.account)
                }
                if !store.apps.isEmpty {
                    Section("Mijn apps") {
                        ForEach(store.apps) { app in
                            Label {
                                Text(app.name).lineLimit(1)
                            } icon: {
                                AppIconView(url: app.iconURL, size: 24, name: app.name)
                            }
                            .tag(SidebarItem.app(app.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("DevTools")
            .toolbar(.hidden, for: .navigationBar)
        } detail: {
            NavigationStack(path: $path) {
                detail(for: selection ?? .home)
                    .navigationDestination(for: ScreenRoute.self) { RouteDestination(route: $0) }
            }
        }
        .onChange(of: selection) { _, _ in path = NavigationPath() }
        .onAppear {
            if let screen = LaunchArgs.screen, ["app", "version", "reviews", "build", "guide"].contains(screen) {
                if screen == "app", let first = store.apps.first { selection = .app(first.id); return }
                for r in ScreenPlan.path(screen, apps: store.apps) { path.append(r) }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .home: DashboardView()
        case .apps: AppsListView()
        case .testflight: TestFlightView()
        case .insights: InsightsView()
        case .account: AccountView()
        case .app(let id):
            if let app = store.apps.first(where: { $0.id == id }) {
                AppDetailView(appID: app.id)
            } else {
                ContentUnavailableView("App niet gevonden", systemImage: "app.dashed")
            }
        }
    }
}

/// First launch: no account linked yet.
struct WelcomeView: View {
    @Environment(DevStore.self) private var store
    @State private var showAdd = false
    @State private var showGuide = false
    @State private var appear = false

    private let features: [(String, String, String)] = [
        ("square.stack.3d.up.fill", "Al je apps", "Iconen, status (Live, In review) en versies in één overzicht."),
        ("square.and.pencil", "Versies & teksten", "Nieuwe versie maken, What's New, beschrijving en keywords invullen, build kiezen en indienen."),
        ("airplane", "TestFlight", "Builds beheren, testgroepen, testers, What to Test en beta-review."),
        ("chart.xyaxis.line", "Insights", "Downloads, updates en opbrengsten per app in Homey-stijl grafieken.")
    ]

    var body: some View {
        ZStack {
            Color(rgb: 0x030A1C).ignoresSafeArea()
            AuroraBackground()
            ScrollView {
                VStack(spacing: 26) {
                    Image("SplashLogo")
                        .resizable().scaledToFit().frame(width: 112, height: 112)
                        .shadow(color: Theme.cyan.opacity(0.5), radius: 26)
                        .scaleEffect(appear ? 1 : 0.6)
                        .padding(.top, 60)
                    VStack(spacing: 8) {
                        Text("Welkom bij DevTools").font(.largeTitle.weight(.heavy)).foregroundStyle(.white)
                        Text("Jouw App Store Connect in je broekzak.").font(.headline).foregroundStyle(.white.opacity(0.75))
                    }
                    .multilineTextAlignment(.center)
                    VStack(spacing: 12) {
                        ForEach(Array(features.enumerated()), id: \.offset) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.element.0)
                                    .font(.title3)
                                    .foregroundStyle(Theme.cyan)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(LS(item.element.1)).font(.headline).foregroundStyle(.white)
                                    Text(LS(item.element.2)).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 20)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1 + Double(item.offset) * 0.08), value: appear)
                        }
                    }
                    Button { showAdd = true } label: { Label("Koppel App Store Connect", systemImage: "key.fill") }
                        .buttonStyle(GradientPillButtonStyle())
                    Button { withAnimation { store.startDemo() } } label: {
                        VStack(spacing: 2) {
                            Label("Bekijk demo", systemImage: "play.rectangle.fill").font(.headline)
                            Text("Bekijk DevTools met voorbeeldgegevens, zonder API-sleutel.").font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { showGuide = true } label: { Label("Hoe kom ik aan een API-sleutel?", systemImage: "book.pages.fill") }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cyan)
                    Text("Je hebt een App Store Connect API-sleutel (.p8) nodig. Maak die aan in App Store Connect → Gebruikers en toegang → Integraties.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAdd) { AccountEditorSheet(existing: nil) }
        .sheet(isPresented: $showGuide) {
            NavigationStack {
                GuideView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { showGuide = false } } }
            }
            .preferredColorScheme(nil)
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { appear = true } }
    }
}

#if targetEnvironment(macCatalyst)
/// No Apple Watch on the Mac.
final class PhoneWatchBridge {
    static let shared = PhoneWatchBridge()
    func activate() {}
    func send(_ snapshot: SharedSnapshot) {}
}
#else
/// Sends the snapshot (and small app icons) to the Apple Watch and answers the
/// watch's "refresh" requests, like HomeyDev.
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()

    func activate() {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(_ snapshot: SharedSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        var context: [String: Any] = ["snapshot": data, "sent": Date().timeIntervalSince1970]
        let icons = Self.watchIcons(for: snapshot)
        if !icons.isEmpty { context["icons"] = icons }
        try? WCSession.default.updateApplicationContext(context)
    }

    /// 48 pt JPEG icons (a few KB each) so the watch can show real app icons.
    static func watchIcons(for snapshot: SharedSnapshot) -> [String: Data] {
        var out: [String: Data] = [:]
        for app in snapshot.apps.prefix(20) {
            guard let url = SharedSnapshot.iconURL(for: app.id), let image = UIImage(contentsOfFile: url.path) else { continue }
            let size = CGSize(width: 48, height: 48)
            let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            if let jpg = small.jpegData(compressionQuality: 0.75) { out[app.id] = jpg }
        }
        return out
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["request"] as? String == "snapshot" else { replyHandler([:]); return }
        let snapshot = SharedSnapshot.load()
        var reply: [String: Any] = [:]
        if !snapshot.apps.isEmpty, let data = try? JSONEncoder().encode(snapshot) {
            reply["snapshot"] = data
            let icons = Self.watchIcons(for: snapshot)
            if !icons.isEmpty { reply["icons"] = icons }
        }
        replyHandler(reply)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { send(SharedSnapshot.load()) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif

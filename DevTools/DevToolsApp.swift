import SwiftUI
import WatchConnectivity

@main
struct DevToolsApp: App {
    @State private var store = DevStore()
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system

    init() { PhoneWatchBridge.shared.activate() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(DevStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
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
        let start = Date()
        let hasCache = !store.apps.isEmpty
        if store.active != nil {
            Task { await store.refresh() }
        }
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

/// iPhone: tab bar. iPad: sidebar.
struct MainView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            SidebarRootView()
        } else {
            TabView {
                NavigationStack { DashboardView() }
                    .tabItem { Label("Home", systemImage: "house.fill") }
                NavigationStack { AppsListView() }
                    .tabItem { Label("Apps", systemImage: "square.stack.3d.up.fill") }
                NavigationStack { TestFlightView() }
                    .tabItem { Label("TestFlight", systemImage: "airplane") }
                NavigationStack { InsightsView() }
                    .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
                NavigationStack { AccountView() }
                    .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
            }
        }
    }
}

enum SidebarItem: Hashable {
    case home, apps, testflight, insights, account
    case app(String)
}

struct SidebarRootView: View {
    @Environment(DevStore.self) private var store
    @State private var selection: SidebarItem? = .home
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
            }
        }
        .onChange(of: selection) { _, _ in path = NavigationPath() }
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
    @State private var showAdd = false
    @State private var appear = false

    private let features: [(String, String, String)] = [
        ("square.stack.3d.up.fill", "Al je apps", "Iconen, status (Live, In review) en versies in één overzicht."),
        ("square.and.pencil", "Versies & teksten", "Nieuwe versie maken, What's New, beschrijving en keywords invullen, build kiezen en indienen."),
        ("airplane", "TestFlight", "Builds beheren, testgroepen, testers, What to Test en beta-review."),
        ("chart.xyaxis.line", "Insights", "Downloads, updates en opbrengsten per app in Homey-stijl grafieken.")
    ]

    var body: some View {
        ZStack {
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
                                    Text(item.element.1).font(.headline).foregroundStyle(.white)
                                    Text(item.element.2).font(.subheadline).foregroundStyle(.white.opacity(0.7))
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
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { appear = true } }
    }
}

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
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { send(SharedSnapshot.load()) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

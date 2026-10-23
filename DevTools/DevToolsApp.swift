import SwiftUI
import WatchConnectivity

@main struct DevToolsApp: App {
    @State private var store=DevStore()
    @State private var showingSplash = true
    @AppStorage("appearance") private var appearance="system"
    init() { PhoneWatchBridge.shared.activate() }
    var body: some Scene {
        WindowGroup {
            ZStack {
                RootScreen()
                    .environment(store)
                if showingSplash {
                    DevToolsSplashView()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
                .task {
                    try? await Task.sleep(for: .seconds(1.45))
                    withAnimation(.easeOut(duration: 0.35)) { showingSplash = false }
                }
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .tint(.blue)
                .task { if store.active != nil { await store.refresh() } }
                .onChange(of:store.lastRefresh) { _,_ in PhoneWatchBridge.shared.send(SharedSnapshot.load()) }
        }
    }
}
final class PhoneWatchBridge:NSObject, WCSessionDelegate {
    static let shared=PhoneWatchBridge()
    func activate(){ if WCSession.isSupported() { WCSession.default.delegate=self;WCSession.default.activate() } }
    func send(_ snapshot:SharedSnapshot){
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, let data=try? JSONEncoder().encode(snapshot) else{return}
        try? WCSession.default.updateApplicationContext(["snapshot":data])
    }
    func session(_ session:WCSession,activationDidCompleteWith activationState:WCSessionActivationState,error:Error?){ }
    func sessionDidBecomeInactive(_ session:WCSession){}
    func sessionDidDeactivate(_ session:WCSession){session.activate()}
}

// DevTools-branded splash presented on every cold launch.
private struct DevToolsSplashView: View {
    @State private var appeared = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.32, blue: 0.78), Color(red: 0.02, green: 0.10, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 15) {
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.24), radius: 22, y: 9)
                Text("DevTools")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Developer Tools for App Store Connect")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                ProgressView().tint(.white).padding(.top, 14)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.94)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { appeared = true } }
    }
}

import SwiftUI
import WatchConnectivity
import WidgetKit

final class WatchBridge:NSObject,ObservableObject,WCSessionDelegate {
    @Published var snapshot=WatchBridge.saved()
    static func saved()->SharedSnapshot {
        guard let data=UserDefaults(suiteName:"group.nl.lrvdlinden.devtools.watch")?.data(forKey:"watchSnapshot"),let value=try? JSONDecoder().decode(SharedSnapshot.self,from:data) else{return .placeholder}
        return value
    }
    override init(){super.init();if WCSession.isSupported(){WCSession.default.delegate=self;WCSession.default.activate()}}
    func session(_ session:WCSession,activationDidCompleteWith activationState:WCSessionActivationState,error:Error?){}
    func session(_ session:WCSession,didReceiveApplicationContext context:[String:Any]){
        if let d=context["snapshot"] as? Data, let value=try? JSONDecoder().decode(SharedSnapshot.self,from:d){
            UserDefaults(suiteName:"group.nl.lrvdlinden.devtools.watch")?.set(d,forKey:"watchSnapshot")
            DispatchQueue.main.async{self.snapshot=value;WidgetCenter.shared.reloadAllTimelines()}
        }
    }
}
@main struct DevToolsWatchApp:App {
    @StateObject private var bridge=WatchBridge()
    @State private var splash = true
    var body:some Scene {
        WindowGroup {
            ZStack {
                WatchDashboard().environmentObject(bridge)
                if splash {
                    ZStack {
                        Color(red: 0.03, green: 0.20, blue: 0.55).ignoresSafeArea()
                        VStack(spacing: 8) {
                            Image("SplashLogo").resizable().scaledToFit().frame(width: 70, height: 70)
                            Text("DevTools").font(.headline).foregroundStyle(.white)
                        }
                    }.transition(.opacity)
                }
            }.task {
                try? await Task.sleep(for: .seconds(1))
                withAnimation { splash = false }
            }
        }
    }
}
struct WatchDashboard:View {
    @EnvironmentObject private var bridge:WatchBridge
    var body:some View {
        NavigationStack {
            List {
                VStack(alignment:.leading){Text("\(bridge.snapshot.apps.count)").font(.system(size:42,weight:.bold));Text("Apps").font(.caption)}
                Label("\(bridge.snapshot.inReview) in review",systemImage:"clock.fill").foregroundStyle(.orange)
                Section("My Apps") {ForEach(bridge.snapshot.apps){app in
                    NavigationLink {VStack(alignment:.leading,spacing:10){Text(app.name).font(.title3.bold());Text("Version \(app.version)");Text(app.state).foregroundStyle(.secondary)}} label:{VStack(alignment:.leading){Text(app.name);Text(app.state).font(.caption2).foregroundStyle(.secondary)}}
                }}
                Text("Syncs from paired iPhone").font(.caption2).foregroundStyle(.secondary)
            }.navigationTitle("DevTools")
        }
    }
}

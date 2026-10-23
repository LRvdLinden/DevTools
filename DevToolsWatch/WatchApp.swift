import SwiftUI
import WatchConnectivity
import WidgetKit

final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snapshot = WatchBridge.saved()

    static let suite = "group.nl.lrvdlinden.devtools.watch"

    static func saved() -> SharedSnapshot {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: "watchSnapshot"),
              let value = try? JSONDecoder().decode(SharedSnapshot.self, from: data) else { return .placeholder }
        return value
    }

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let d = session.receivedApplicationContext["snapshot"] as? Data { apply(d) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        if let d = context["snapshot"] as? Data { apply(d) }
    }

    private func apply(_ d: Data) {
        guard let value = try? JSONDecoder().decode(SharedSnapshot.self, from: d) else { return }
        UserDefaults(suiteName: Self.suite)?.set(d, forKey: "watchSnapshot")
        DispatchQueue.main.async {
            self.snapshot = value
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

@main
struct DevToolsWatchApp: App {
    @StateObject private var bridge = WatchBridge()
    @State private var splash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                WatchDashboard().environmentObject(bridge)
                if splash {
                    WatchSplash()
                        .transition(.opacity.combined(with: .scale(scale: 1.2)))
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeInOut(duration: 0.45)) { splash = false }
            }
        }
    }
}

struct WatchSplash: View {
    @State private var on = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.05, green: 0.35, blue: 0.95), Color(red: 0.01, green: 0.04, blue: 0.12)],
                           center: .center, startRadius: 5, endRadius: 140)
                .ignoresSafeArea()
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Circle()
                    .trim(from: 0, to: on ? 0.8 : 0)
                    .stroke(AngularGradient(colors: [Color.cyan.opacity(0), .cyan, .white], center: .center),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 104, height: 104)
                    .rotationEffect(.degrees((t * 120).truncatingRemainder(dividingBy: 360)))
            }
            VStack(spacing: 8) {
                Image("SplashLogo").resizable().scaledToFit().frame(width: 64, height: 64)
                    .scaleEffect(on ? 1 : 0.4)
                    .opacity(on ? 1 : 0)
                    .shadow(color: .cyan.opacity(0.6), radius: 10)
                Text("DevTools").font(.headline.weight(.heavy)).foregroundStyle(.white)
                    .opacity(on ? 1 : 0)
                    .offset(y: on ? 0 : 8)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) { on = true } }
    }
}

struct WatchDashboard: View {
    @EnvironmentObject private var bridge: WatchBridge

    var body: some View {
        let s = bridge.snapshot
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 2) {
                    if let d = s.downloads {
                        Text(d.formatted(.number.notation(.compactName))).font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(.cyan)
                        Text("downloads · \(s.downloadsRange ?? "")").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("\(s.apps.count)").font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("apps").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Label("\(s.liveCount) live", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Spacer()
                    Label("\(s.inReview)", systemImage: "hourglass").foregroundStyle(s.inReview > 0 ? .orange : .secondary)
                }
                .font(.caption.weight(.semibold))
                if let p = s.proceeds, let c = s.currency {
                    Label(p.formatted(.currency(code: c)), systemImage: "eurosign.circle.fill").foregroundStyle(.green).font(.caption)
                }
                Section("Mijn apps") {
                    ForEach(s.apps) { app in
                        NavigationLink {
                            WatchAppDetail(app: app)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).font(.headline).lineLimit(1)
                                Text(app.statusLabel).font(.caption2).foregroundStyle(color(for: app.state))
                            }
                        }
                    }
                }
                Text("Synchroniseert via je iPhone · \(s.updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .navigationTitle("DevTools")
        }
    }

    private func color(for state: String) -> Color {
        switch state {
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION": return .green
        case "WAITING_FOR_REVIEW", "IN_REVIEW": return .orange
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": return .red
        default: return .secondary
        }
    }
}

struct WatchAppDetail: View {
    let app: WidgetAppSummary

    var body: some View {
        List {
            Text(app.name).font(.title3.bold())
            LabeledContent("Status", value: app.statusLabel)
            if let live = app.liveVersion { LabeledContent("Live", value: live) }
            if let p = app.pendingVersion {
                LabeledContent("Volgende", value: p)
                if let ps = app.pendingState { LabeledContent("Stand", value: SharedSnapshot.label(for: ps)) }
            }
            if let b = app.build { LabeledContent("Build", value: b) }
            if let d = app.downloads { LabeledContent("Downloads", value: d.formatted()) }
        }
        .navigationTitle(app.name)
    }
}

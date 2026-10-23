import SwiftUI
import Charts
import Observation
import WatchConnectivity
import WidgetKit
import UIKit

@main
struct DevToolsWatchApp: App {
    @State private var store = WatchStore()
    @State private var splash = !ProcessInfo.processInfo.arguments.contains("-noSplash")

    var body: some Scene {
        WindowGroup {
            ZStack {
                NavigationStack {
                    WatchRootView()
                }
                .environment(store)
                .tint(Watch.accent)
                if splash {
                    WatchSplash()
                        .transition(.opacity.combined(with: .scale(scale: 1.2)))
                        .zIndex(1)
                }
            }
            .task {
                store.activate()
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeInOut(duration: 0.4)) { splash = false }
            }
        }
    }
}

// MARK: - Store (same idea as HomeyDev: context from the iPhone + "Ophalen" request)

@MainActor
@Observable
final class WatchStore: NSObject {
    private(set) var snapshot: SharedSnapshot?
    private(set) var refreshing = false
    private(set) var message: String?
    private(set) var iconVersion = 0

    private static let key = "watchSnapshot"

    override init() {
        super.init()
        let saved = SharedSnapshot.load(suite: SharedSnapshot.watchSuite, key: Self.key)
        snapshot = saved.apps.isEmpty ? nil : saved
        if ProcessInfo.processInfo.arguments.contains("-demo") { snapshot = .sample }
    }

    func activate() {
        guard WCSession.isSupported(), !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the iPhone for its latest summary.
    func refresh() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            message = L("iPhone niet bereikbaar. Open DevTools op je iPhone.")
            return
        }
        refreshing = true
        message = nil
        session.sendMessage(["request": "snapshot"], replyHandler: { reply in
            let data = reply["snapshot"] as? Data
            let icons = reply["icons"] as? [String: Data]
            Task { @MainActor in
                self.refreshing = false
                if let data { self.apply(data, icons: icons) } else { self.message = L("Open DevTools op je iPhone om gegevens te laden.") }
            }
        }, errorHandler: { error in
            let text = error.localizedDescription
            Task { @MainActor in
                self.refreshing = false
                self.message = text
            }
        })
    }

    fileprivate func apply(_ data: Data, icons: [String: Data]?) {
        guard let new = try? JSONDecoder().decode(SharedSnapshot.self, from: data) else { return }
        snapshot = new
        UserDefaults(suiteName: SharedSnapshot.watchSuite)?.set(data, forKey: Self.key)
        if let icons, !icons.isEmpty {
            for (id, png) in icons {
                guard let url = SharedSnapshot.iconURL(for: id, suite: SharedSnapshot.watchSuite) else { continue }
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? png.write(to: url)
            }
            iconVersion += 1
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let data = context["snapshot"] as? Data
        let icons = context["icons"] as? [String: Data]
        Task { @MainActor in
            if let data { self.apply(data, icons: icons) }
            if self.snapshot == nil { self.refresh() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext["snapshot"] as? Data
        let icons = applicationContext["icons"] as? [String: Data]
        Task { @MainActor in if let data { self.apply(data, icons: icons) } }
    }
}

// MARK: - Styling

enum Watch {
    static let accent = Color(red: 0.10, green: 0.55, blue: 1.0)
    static let cyan = Color(red: 0.24, green: 0.83, blue: 1.0)
    static let live = Color.green
    static let review = Color.orange
    static let pending = Color(red: 0.6, green: 0.52, blue: 1.0)

    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func number(_ n: Int) -> String { n.formatted(.number) }
    static func signed(_ n: Int) -> String { n > 0 ? "+\(compact(n))" : n < 0 ? "−\(compact(-n))" : "±0" }
    static func money(_ v: Double?, _ c: String?) -> String {
        guard let v else { return "—" }
        guard let c, !c.isEmpty else { return String(format: "%.0f", v) }
        return v.formatted(.currency(code: c).precision(.fractionLength(0)))
    }

    static func color(for state: String) -> Color {
        switch state {
        case "READY_FOR_SALE": return live
        case "READY_FOR_DISTRIBUTION": return cyan
        case "WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW", "MISSING_EXPORT_COMPLIANCE": return review
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": return .red
        case "PENDING_DEVELOPER_RELEASE": return pending
        default: return .secondary
        }
    }
}

struct WatchAppIcon: View {
    let app: WidgetAppSummary
    var size: CGFloat = 26
    @Environment(WatchStore.self) private var store

    var body: some View {
        let _ = store.iconVersion
        Group {
            if let url = SharedSnapshot.iconURL(for: app.id, suite: SharedSnapshot.watchSuite), let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let demo = SharedSnapshot.demoIcon(for: app.name), let img = UIImage(named: demo) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Watch.accent, Watch.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(String(app.name.prefix(1))).font(.system(size: size * 0.45, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

// MARK: - Splash

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

// MARK: - Pages: Overzicht, Apps, Aandacht (vertical paging, like HomeyDev)

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var page: Int = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-page"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }()

    var body: some View {
        if let snapshot = store.snapshot {
            TabView(selection: $page) {
                WatchOverviewView(snapshot: snapshot).tag(0)
                WatchAppsView(snapshot: snapshot).tag(1)
                WatchAttentionView(snapshot: snapshot).tag(2)
            }
            .tabViewStyle(.verticalPage)
        } else {
            WatchEmptyView()
        }
    }
}

struct WatchEmptyView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image("SplashLogo").resizable().scaledToFit().frame(width: 52, height: 52)
                Text("DevTools").font(.headline)
                Text("Open de app op je iPhone. Je gegevens komen dan vanzelf naar je Apple Watch.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { store.refresh() } label: {
                    if store.refreshing { ProgressView() } else { Label("Ophalen", systemImage: "arrow.clockwise") }
                }
                if let message = store.message {
                    Text(message).font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct WatchOverviewView: View {
    let snapshot: SharedSnapshot
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    if let d = snapshot.downloads {
                        Text("Downloads · \(snapshot.downloadsRange ?? "")").font(.caption2).foregroundStyle(.secondary)
                        Text(Watch.number(d))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        if let d7 = snapshot.delta7 {
                            Text("\(Watch.signed(d7)) · 7d")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(d7 >= 0 ? .green : .red)
                        }
                    } else {
                        Text("Apps").font(.caption2).foregroundStyle(.secondary)
                        Text("\(snapshot.apps.count)")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text("Vul je vendornummer in op de iPhone voor downloads").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

                if snapshot.totalHistory.count > 1 {
                    Chart(Array(snapshot.totalHistory.suffix(30)), id: \.date) { (p: HistoryPoint) in
                        AreaMark(x: .value("Dag", p.date), y: .value("Downloads", p.value))
                            .foregroundStyle(Watch.accent.opacity(0.25).gradient)
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Dag", p.date), y: .value("Downloads", p.value))
                            .foregroundStyle(Watch.accent)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 44)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    WatchStat(title: "Live", value: "\(snapshot.liveCount)", icon: "checkmark.seal.fill", tint: Watch.live)
                    WatchStat(title: "In review", value: "\(snapshot.inReview)", icon: "hourglass",
                              tint: snapshot.inReview == 0 ? .secondary : Watch.review)
                    WatchStat(title: "Opbrengst", value: Watch.money(snapshot.proceeds, snapshot.currency), icon: "eurosign.circle.fill", tint: Watch.live)
                    WatchStat(title: "Rating", value: snapshot.averageRating.map { String(format: "%.1f", $0) } ?? "—", icon: "star.fill", tint: .yellow)
                }

                Text("\(snapshot.accountName ?? "DevTools") · \(snapshot.updated.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .navigationTitle("DevTools")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.refresh() } label: {
                    if store.refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
    }
}

struct WatchStat: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(LS(title), systemImage: icon).font(.system(size: 11)).foregroundStyle(tint).lineLimit(1)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct WatchAppsView: View {
    let snapshot: SharedSnapshot

    var body: some View {
        List(snapshot.topApps) { (app: WidgetAppSummary) in
            NavigationLink { WatchAppDetailView(app: app, currency: snapshot.currency) } label: { WatchAppRow(app: app) }
        }
        .navigationTitle("Mijn apps")
    }
}

struct WatchAppRow: View {
    let app: WidgetAppSummary

    var body: some View {
        HStack(spacing: 8) {
            WatchAppIcon(app: app, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.footnote.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    if let d = app.downloads { Text(Watch.compact(d)).monospacedDigit() }
                    if let d7 = app.delta7, d7 != 0 {
                        Text(Watch.signed(d7)).foregroundStyle(d7 > 0 ? .green : .red)
                    }
                    if app.downloads == nil { Text(app.statusLabel).foregroundStyle(Watch.color(for: app.state)) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle().fill(Watch.color(for: app.activeState)).frame(width: 7, height: 7)
        }
    }
}

struct WatchAppDetailView: View {
    let app: WidgetAppSummary
    var currency: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    WatchAppIcon(app: app, size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.downloads.map { Watch.number($0) } ?? "—")
                            .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.6)
                        Text("downloads").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let d7 = app.delta7 {
                    Text("\(Watch.signed(d7)) · 7d").font(.caption.monospacedDigit()).foregroundStyle(d7 >= 0 ? .green : .red)
                }

                if app.series.count > 1 {
                    Chart(Array(app.series.suffix(30)), id: \.date) { (p: HistoryPoint) in
                        LineMark(x: .value("Dag", p.date), y: .value("Downloads", p.value))
                            .foregroundStyle(Watch.accent)
                            .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 50)
                }

                VStack(alignment: .leading, spacing: 4) {
                    row("Status", app.statusLabel, Watch.color(for: app.state))
                    if let live = app.liveVersion { row("Live", "v\(live)", Watch.live) }
                    if let p = app.pendingVersion {
                        let state = app.pendingState ?? ""
                        row("Volgende", "v\(p) · \(SharedSnapshot.label(for: state))", Watch.color(for: state))
                    }
                    if let b = app.build { row("Build", b, Watch.cyan) }
                    if let u = app.updates { row("Updates", Watch.compact(u), Watch.pending) }
                    if let p = app.proceeds { row("Opbrengst", Watch.money(p, currency), Watch.live) }
                    if let r = app.rating, (app.ratingCount ?? 0) > 0 { row("Rating", String(format: "%.1f ★", r), .yellow) }
                }
            }
        }
        .navigationTitle(app.name)
    }

    private func row(_ title: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            Text(LS(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.caption)
    }
}

struct WatchAttentionView: View {
    let snapshot: SharedSnapshot

    var body: some View {
        List {
            Section("In review") {
                if snapshot.inReviewApps.isEmpty {
                    Label("Niets in review", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.footnote)
                }
                ForEach(snapshot.inReviewApps) { (app: WidgetAppSummary) in
                    NavigationLink { WatchAppDetailView(app: app, currency: snapshot.currency) } label: {
                        HStack(spacing: 6) {
                            WatchAppIcon(app: app, size: 22)
                            VStack(alignment: .leading) {
                                Text(app.name).font(.footnote.weight(.semibold)).lineLimit(1)
                                Text("v\(app.pendingVersion ?? app.version) · \(SharedSnapshot.label(for: app.activeState))").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            Section("Aandacht nodig") {
                if snapshot.attentionApps.isEmpty {
                    Label("Alles in orde", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.footnote)
                }
                ForEach(snapshot.attentionApps.prefix(8)) { (app: WidgetAppSummary) in
                    NavigationLink { WatchAppDetailView(app: app, currency: snapshot.currency) } label: {
                        HStack(spacing: 6) {
                            WatchAppIcon(app: app, size: 22)
                            VStack(alignment: .leading) {
                                Text(app.name).font(.footnote).lineLimit(1)
                                Text(attentionText(app)).font(.caption2).foregroundStyle(Watch.color(for: attentionState(app))).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Aandacht")
    }

    private func attentionState(_ app: WidgetAppSummary) -> String {
        app.buildState == "MISSING_EXPORT_COMPLIANCE" ? "MISSING_EXPORT_COMPLIANCE" : app.activeState
    }

    private func attentionText(_ app: WidgetAppSummary) -> String {
        SharedSnapshot.label(for: attentionState(app))
    }
}

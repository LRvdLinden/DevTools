import SwiftUI

// MARK: - TestFlight feedback (screenshots + comments) and crash reports, diagnostics per build

struct FeedbackView: View {
    let app: AppSummary
    var buildID: String? = nil
    @Environment(DevStore.self) private var store
    @State private var kind = 0
    @State private var screenshots: [JRes] = []
    @State private var crashes: [JRes] = []
    @State private var builds: [String: BuildInfo] = [:]
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        let items = (kind == 0 ? screenshots : crashes).sorted { ($0.date("createdDate") ?? .distantPast) > ($1.date("createdDate") ?? .distantPast) }
        List {
            Section {
                Picker("Soort", selection: $kind) {
                    Text("Feedback (\(screenshots.count))").tag(0)
                    Text("Crashes (\(crashes.count))").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            ForEach(items) { f in
                NavigationLink { FeedbackDetailView(item: f, isCrash: kind == 1, build: f.rel("build").flatMap { builds[$0] }) { await load() } } label: {
                    FeedbackRow(item: f, isCrash: kind == 1, build: f.rel("build").flatMap { builds[$0] })
                }
            }
            .cardRows()
        }
        .themedList()
        .overlay {
            if loading && screenshots.isEmpty && crashes.isEmpty { ProgressView() }
            else if !loading && items.isEmpty && error == nil {
                ContentUnavailableView(LS(kind == 0 ? "Nog geen feedback" : "Geen crashmeldingen"), systemImage: kind == 0 ? "bubble.left.and.text.bubble.right" : "checkmark.shield")
            }
        }
        .navigationTitle(buildID == nil ? "TestFlight-feedback" : "Feedback voor deze build")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        var q: [(String, String)] = [("limit", "100")]
        if let buildID { q.append(("filter[build]", buildID)) }
        let query = q
        do {
            async let s = api.jget("/v1/apps/\(app.id)/betaFeedbackScreenshotSubmissions", query, all: true, max: 300)
            async let c = api.jget("/v1/apps/\(app.id)/betaFeedbackCrashSubmissions", query, all: true, max: 300)
            async let b = api.builds(appID: app.id, limit: 100)
            screenshots = try await s.data
            crashes = try await c.data
            if let list = try? await b { builds = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct FeedbackRow: View {
    let item: JRes
    let isCrash: Bool
    let build: BuildInfo?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isCrash, let first = (item.list("screenshots").first as? [String: Any])?["url"] as? String, let url = URL(string: first) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Theme.cardRaised }
                    .frame(width: 44, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: isCrash ? "exclamationmark.triangle.fill" : "text.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(isCrash ? Theme.rejected : Theme.accent)
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.s("comment").flatMap { $0.isEmpty ? nil : $0 } ?? L("Geen opmerking"))
                    .font(.subheadline).lineLimit(3)
                Text([item.s("email"), item.s("deviceModel"), item.s("osVersion").map { "OS \($0)" }, build?.title].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(2)
                Text(Fmt.relative(item.date("createdDate"))).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct FeedbackDetailView: View {
    let item: JRes
    let isCrash: Bool
    let build: BuildInfo?
    var onDelete: () async -> Void
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var log: String?
    @State private var loadingLog = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var fullScreen: URL?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if let c = item.s("comment"), !c.isEmpty {
                Section("Opmerking") { Text(c).textSelection(.enabled) }.cardRows()
            }
            let shots = item.list("screenshots").compactMap { $0 as? [String: Any] }
            if !shots.isEmpty {
                Section("Screenshots") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(shots.enumerated()), id: \.offset) { _, s in
                                if let u = (s["url"] as? String).flatMap(URL.init(string:)) {
                                    Button { fullScreen = u } label: {
                                        AsyncImage(url: u) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                                            .frame(height: 260)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .cardRows()
            }
            Section("Toestel") {
                row("Tester", item.s("email"))
                row("Build", build?.title)
                row("Toestel", item.s("deviceModel"))
                row("Besturingssysteem", item.s("osVersion"))
                row("Taal", item.s("locale"))
                row("Verbinding", item.s("connectionType").map(Pretty.label))
                row("Batterij", item.i("batteryPercentage").map { "\($0)%" })
                if let total = item.dbl("diskBytesTotal"), let free = item.dbl("diskBytesAvailable"), total > 0 {
                    row("Vrije opslag", "\(ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))")
                }
                if let up = item.dbl("appUptimeInMilliseconds") { row("App actief", Duration.milliseconds(up).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))) }
                if let w = item.i("screenWidthInPoints"), let h = item.i("screenHeightInPoints") { row("Scherm", "\(w) × \(h) pt") }
                row("Datum", Fmt.date(item.date("createdDate")))
            }
            .cardRows()
            if isCrash {
                Section("Crashlog") {
                    if let log {
                        ScrollView(.horizontal) {
                            Text(log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).padding(.vertical, 4)
                        }
                        .frame(maxHeight: 420)
                        ShareLink(item: log) { Label("Deel crashlog", systemImage: "square.and.arrow.up") }
                        Button { UIPasteboard.general.string = log } label: { Label("Kopieer crashlog", systemImage: "doc.on.doc") }
                    } else if loadingLog {
                        ProgressView()
                    } else {
                        Button { Task { await loadLog() } } label: { Label("Crashlog laden", systemImage: "doc.text.magnifyingglass") }
                    }
                }
                .cardRows()
            }
            Section {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Verwijder", systemImage: "trash") }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(isCrash ? "Crash" : "Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task { if isCrash { await loadLog() } }
        .confirmationDialog("Feedback verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) { Task { await delete() } }
        }
        .sheet(item: Binding(get: { fullScreen.map(IdentURL.init) }, set: { fullScreen = $0?.url })) { u in
            NavigationStack {
                AsyncImage(url: u.url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .padding()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Sluit") { fullScreen = nil } } }
            }
        }
    }

    @ViewBuilder private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty { LabeledContent(LS(title), value: value) }
    }

    private func loadLog() async {
        guard let api = store.api, log == nil else { return }
        loadingLog = true
        defer { loadingLog = false }
        do {
            let doc = try await api.jget("/v1/betaFeedbackCrashSubmissions/\(item.id)/crashLog")
            log = doc.data.first?.s("logText") ?? L("Geen crashlog beschikbaar")
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        guard let api = store.api else { return }
        let path = isCrash ? "/v1/betaFeedbackCrashSubmissions/\(item.id)" : "/v1/betaFeedbackScreenshotSubmissions/\(item.id)"
        do { try await api.jdelete(path); await onDelete(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct IdentURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Diagnostics (hangs, disk writes, launches) per build

struct DiagnosticsView: View {
    let buildID: String
    @Environment(DevStore.self) private var store
    @State private var loader = Loader()

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            ForEach(loader.doc.data.sorted { ($0.dbl("weight") ?? 0) > ($1.dbl("weight") ?? 0) }) { s in
                NavigationLink { DiagnosticLogView(signature: s) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(typeLabel(s.s("diagnosticType"))).font(.caption.weight(.bold)).foregroundStyle(Theme.review)
                            Spacer()
                            if let w = s.dbl("weight") { Text(String(format: "%.1f%%", w * (w <= 1 ? 100 : 1))).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary) }
                        }
                        Text(s.str("signature")).font(.caption.monospaced()).lineLimit(3)
                        if let dir = s.obj("insight")?["direction"] as? String, dir != "UNDEFINED" {
                            Label(dir == "UP" ? L("Neemt toe") : L("Neemt af"), systemImage: dir == "UP" ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2).foregroundStyle(dir == "UP" ? Theme.rejected : Theme.live)
                        }
                    }
                }
            }
            .cardRows()
        }
        .themedList()
        .overlay { ListStatus(loader: loader, empty: "Geen diagnosegegevens voor deze build") }
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func typeLabel(_ t: String?) -> String {
        switch t {
        case "HANGS": return L("Vastlopers")
        case "DISK_WRITES": return L("Schrijfacties")
        case "LAUNCHES": return L("Opstarten")
        default: return Pretty.label(t)
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/builds/\(buildID)/diagnosticSignatures", [("limit", "200")], all: true) }
    }
}

struct DiagnosticLogView: View {
    let signature: JRes
    @Environment(DevStore.self) private var store
    @State private var text: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(signature.str("signature")).font(.footnote.monospaced()).textSelection(.enabled)
                if let error { ErrorBanner(message: error) }
                if let text {
                    Text(text).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    ShareLink(item: text) { Label("Deel log", systemImage: "square.and.arrow.up") }
                } else if error == nil { ProgressView() }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        do {
            let data = try await api.raw("/v1/diagnosticSignatures/\(signature.id)/logs", accept: "application/vnd.apple.diagnostic-logs+json, application/json")
            text = Self.render(data)
        } catch { self.error = error.localizedDescription }
    }

    /// Turns the call stack trees into readable lines (binary  symbol), with the metadata on top.
    static func render(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return String(decoding: data, as: UTF8.self) }
        var lines: [String] = []
        func frames(_ node: Any, depth: Int) {
            if let d = node as? [String: Any] {
                if d["symbolName"] != nil || d["binaryName"] != nil {
                    let indent = String(repeating: "  ", count: min(depth, 30))
                    let count = (d["sampleCount"] as? Int).map { "[\($0)] " } ?? ""
                    lines.append("\(indent)\(count)\(d["binaryName"] as? String ?? "?")  \(d["symbolName"] as? String ?? "")")
                    for sub in (d["subFrames"] as? [Any]) ?? [] { frames(sub, depth: depth + 1) }
                    return
                }
                if let meta = d["diagnosticMetaData"] as? [String: Any] {
                    lines.append(meta.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                    lines.append("")
                }
                for (k, v) in d where k != "diagnosticMetaData" { frames(v, depth: depth) }
            } else if let a = node as? [Any] {
                a.forEach { frames($0, depth: depth) }
            }
        }
        frames(json, depth: 0)
        if lines.isEmpty, let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            return String(decoding: pretty, as: UTF8.self)
        }
        return lines.joined(separator: "\n")
    }
}

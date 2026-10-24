import SwiftUI

// MARK: - Xcode Cloud: workflows, build runs, start a build

enum CIState {
    /// Combined state of a build run or action for the badge.
    static func state(_ r: JRes) -> String {
        let progress = r.str("executionProgress")
        if progress == "PENDING" { return "CI_PENDING" }
        if progress == "RUNNING" { return "CI_RUNNING" }
        return "CI_" + r.str("completionStatus", "COMPLETE")
    }

    static func color(_ r: JRes) -> Color {
        switch state(r) {
        case "CI_SUCCEEDED": return Theme.live
        case "CI_FAILED", "CI_ERRORED": return Theme.rejected
        case "CI_RUNNING", "CI_PENDING": return Theme.review
        default: return Theme.textSecondary
        }
    }

    static func label(_ r: JRes) -> String {
        switch state(r) {
        case "CI_PENDING": return L("In de wachtrij")
        case "CI_RUNNING": return L("Bezig")
        case "CI_SUCCEEDED": return L("Geslaagd")
        case "CI_FAILED": return L("Mislukt")
        case "CI_ERRORED": return L("Fout")
        case "CI_CANCELED": return L("Geannuleerd")
        case "CI_SKIPPED": return L("Overgeslagen")
        default: return Pretty.label(r.s("completionStatus"))
        }
    }

    static func icon(_ r: JRes) -> String {
        switch state(r) {
        case "CI_SUCCEEDED": return "checkmark.circle.fill"
        case "CI_FAILED", "CI_ERRORED": return "xmark.octagon.fill"
        case "CI_RUNNING": return "gearshape.2.fill"
        case "CI_PENDING": return "clock.fill"
        default: return "minus.circle.fill"
        }
    }
}

struct CIBadge: View {
    let run: JRes
    var body: some View {
        Label(CIState.label(run), systemImage: CIState.icon(run))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(CIState.color(run).opacity(0.15), in: Capsule())
            .foregroundStyle(CIState.color(run))
            .fixedSize()
    }
}

struct XcodeCloudView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var product: JRes?
    @State private var workflows: [JRes] = []
    @State private var runs: [String: [JRes]] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var noProduct = false

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if noProduct {
                ContentUnavailableView {
                    Label("Xcode Cloud is niet ingesteld", systemImage: "cloud")
                } description: {
                    Text("Stel Xcode Cloud eenmalig in via Xcode (Product → Xcode Cloud → Create Workflow). Daarna kun je hier builds starten en volgen.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(workflows) { w in
                Section {
                    NavigationLink { WorkflowView(app: app, product: product, workflow: w) } label: {
                        InfoRow(title: w.str("name"),
                                subtitle: w.s("description") ?? (w.b("isEnabled") == false ? L("Uitgeschakeld") : nil),
                                icon: "flowchart.fill", tint: w.b("isEnabled") == false ? Theme.textSecondary : Theme.accent)
                    }
                    ForEach((runs[w.id] ?? []).prefix(3)) { r in
                        NavigationLink { BuildRunView(run: r) } label: { BuildRunRow(run: r) }
                    }
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay { if loading && workflows.isEmpty && !noProduct { ProgressView() } }
        .navigationTitle("Xcode Cloud")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do {
            let p = try await api.jget("/v1/apps/\(app.id)/ciProduct")
            guard let prod = p.data.first else { noProduct = true; return }
            product = prod
            noProduct = false
            workflows = try await api.jget("/v1/ciProducts/\(prod.id)/workflows", [("limit", "50")], all: true).data
            for w in workflows {
                let r = try? await api.jget("/v1/ciWorkflows/\(w.id)/buildRuns", [("limit", "10"), ("sort", "-number")])
                runs[w.id] = (r?.data ?? []).sorted { ($0.i("number") ?? 0) > ($1.i("number") ?? 0) }
            }
            error = nil
        } catch let e as ConnectError where e.status == 404 {
            noProduct = true
        } catch { self.error = error.localizedDescription }
    }
}

struct BuildRunRow: View {
    let run: JRes
    var body: some View {
        let commit = run.obj("sourceCommit")
        let message = (commit?["message"] as? String)?.components(separatedBy: "\n").first ?? ""
        HStack(spacing: 10) {
            Text("#\(run.i("number") ?? 0)").font(.subheadline.weight(.bold).monospacedDigit()).frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.isEmpty ? Pretty.label(run.s("startReason")) : message).font(.caption).lineLimit(1)
                Text(Fmt.relative(run.date("createdDate"))).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            CIBadge(run: run)
        }
    }
}

struct WorkflowView: View {
    let app: AppSummary
    let product: JRes?
    let workflow: JRes
    @Environment(DevStore.self) private var store
    @State private var runs: [JRes] = []
    @State private var refs: [JRes] = []
    @State private var selectedRef = ""
    @State private var working = false
    @State private var error: String?
    @State private var feedback: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            Section {
                if !refs.isEmpty {
                    Picker("Branch of tag", selection: $selectedRef) {
                        Text("Standaard (volgens workflow)").tag("")
                        ForEach(refs) { r in
                            Label(r.str("name"), systemImage: r.s("kind") == "TAG" ? "tag" : "arrow.triangle.branch").tag(r.id)
                        }
                    }
                }
                Button { Task { await start() } } label: { Label("Start build", systemImage: "play.fill") }
                    .disabled(working || workflow.b("isEnabled") == false)
            } footer: {
                if workflow.b("isEnabled") == false { Text("Deze workflow is uitgeschakeld in Xcode.") }
            }
            .cardRows()
            Section("Builds") {
                ForEach(runs) { r in
                    NavigationLink { BuildRunView(run: r) } label: { BuildRunRow(run: r) }
                }
                if runs.isEmpty { Text("Nog geen builds").font(.footnote).foregroundStyle(Theme.textSecondary) }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(workflow.str("name"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        do {
            runs = try await api.jget("/v1/ciWorkflows/\(workflow.id)/buildRuns", [("limit", "50"), ("sort", "-number")]).data
                .sorted { ($0.i("number") ?? 0) > ($1.i("number") ?? 0) }
            if refs.isEmpty {
                let repos = try? await api.jget("/v1/ciWorkflows/\(workflow.id)/repository")
                if let repo = repos?.data.first {
                    let r = try? await api.jget("/v1/scmRepositories/\(repo.id)/gitReferences", [("limit", "200")], all: true, max: 400)
                    refs = (r?.data ?? []).filter { $0.b("isDeleted") != true }.sorted { $0.str("name") < $1.str("name") }
                }
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func start() async {
        guard let api = store.api else { return }
        working = true
        defer { working = false }
        var rels: [String: (String, String)] = ["workflow": ("ciWorkflows", workflow.id)]
        if !selectedRef.isEmpty { rels["sourceBranchOrTag"] = ("scmGitReferences", selectedRef) }
        do {
            try await api.jcreate("/v1/ciBuildRuns", type: "ciBuildRuns", relationships: rels)
            feedback = L("Build gestart")
            try? await Task.sleep(for: .seconds(2))
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct BuildRunView: View {
    let run: JRes
    @Environment(DevStore.self) private var store
    @State private var current: JRes?
    @State private var actions: [JRes] = []
    @State private var error: String?

    var body: some View {
        let r = current ?? run
        let commit = r.obj("sourceCommit")
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            Section {
                HStack { Text("Build #\(r.i("number") ?? 0)").font(.title3.weight(.bold)); Spacer(); CIBadge(run: r) }
                LabeledContent("Gestart", value: Fmt.date(r.date("startedDate") ?? r.date("createdDate")))
                if let f = r.date("finishedDate") { LabeledContent("Klaar", value: Fmt.date(f)) }
                if let s = r.date("startedDate"), let f = r.date("finishedDate") {
                    LabeledContent("Duur", value: Duration.seconds(f.timeIntervalSince(s)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                }
                LabeledContent("Reden", value: Pretty.label(r.s("startReason")))
            }
            .cardRows()
            if let commit {
                Section("Commit") {
                    if let m = commit["message"] as? String { Text(m).font(.footnote) }
                    if let sha = commit["commitSha"] as? String { LabeledContent("SHA", value: String(sha.prefix(10))).font(.caption.monospaced()) }
                    if let a = (commit["author"] as? [String: Any])?["displayName"] as? String { LabeledContent("Auteur", value: a) }
                }
                .cardRows()
            }
            Section("Acties") {
                ForEach(actions) { a in
                    let issues = a.obj("issueCounts") ?? [:]
                    let errors = (issues["errors"] as? Int ?? 0)
                    let warnings = (issues["warnings"] as? Int ?? 0) + (issues["analyzerWarnings"] as? Int ?? 0)
                    let fails = issues["testFailures"] as? Int ?? 0
                    HStack {
                        InfoRow(title: a.str("name"), subtitle: Pretty.label(a.s("actionType")) + (errors + warnings + fails > 0 ? " · " + L("\(errors) fouten, \(warnings) waarschuwingen, \(fails) testfouten") : ""))
                        CIBadge(run: a)
                    }
                }
                if actions.isEmpty { Text("Nog geen acties").font(.footnote).foregroundStyle(Theme.textSecondary) }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Build #\(r.i("number") ?? 0)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = store.api else { return }
        do {
            current = try await api.jget("/v1/ciBuildRuns/\(run.id)").data.first
            actions = try await api.jget("/v1/ciBuildRuns/\(run.id)/actions", [("limit", "50")]).data
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

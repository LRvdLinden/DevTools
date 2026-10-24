import SwiftUI

/// TestFlight overview: every app with its newest build.
struct TestFlightView: View {
    @Environment(DevStore.self) private var store
    @State private var query = ""

    var body: some View {
        let apps = store.apps
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.latestBuild?.uploaded ?? .distantPast) > ($1.latestBuild?.uploaded ?? .distantPast) }
        List {
            Section {
                BetaUsageTiles(usage: store.betaTotal, loading: store.betaLoading && store.betaUsage.isEmpty)
            } header: { Text("TestFlight-gebruik") } footer: {
                Text("Totaal van alle builds van al je apps, volgens TestFlight.")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            let attention = apps.filter { $0.latestBuild?.needsCompliance == true }
            if !attention.isEmpty {
                Section {
                    ForEach(attention) { app in
                        NavigationLink { BuildDetailView(app: app, buildID: app.latestBuild?.id ?? "") } label: {
                            Label("\(app.name): export compliance invullen", systemImage: "exclamationmark.shield.fill")
                                .foregroundStyle(Theme.review)
                        }
                    }
                }
                .cardRows()
            }
            Section("Laatste builds") {
                ForEach(apps) { app in
                    NavigationLink { AppBuildsView(app: app) } label: {
                        HStack(spacing: 12) {
                            AppIconView(url: app.iconURL, size: 42, name: app.name)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if let b = app.latestBuild {
                                    Text("\(b.title) · \(Fmt.relative(b.uploaded))").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                                } else {
                                    Text("Geen builds").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer()
                            if let u = store.betaUsage[app.id] { InstallCount(value: u.installs) }
                            if let b = app.latestBuild { StateBadge(state: b.displayState, compact: true) }
                        }
                    }
                }
            }
            .cardRows()
        }
        .themedList()
        .searchable(text: $query, prompt: "Zoek app")
        .navigationTitle("TestFlight")
        .task { await store.refreshBetaUsage() }
        .refreshable { await store.refresh(); await store.refreshBetaUsage(force: true) }
        .overlay { if store.apps.isEmpty && store.loading { ProgressView() } }
    }
}

/// All builds of one app, grouped by marketing version.
struct AppBuildsView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var builds: [BuildInfo] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showExpired = false
    @State private var expireTarget: BuildInfo?
    @State private var feedback: String?

    struct BuildGroup: Identifiable {
        let id: String
        var builds: [BuildInfo]
    }

    private var groups: [BuildGroup] {
        let list = builds.filter { showExpired || !$0.expired }
        var out: [BuildGroup] = []
        for b in list {
            let key = b.marketingVersion.isEmpty ? L("Overig") : "\(Platform.label(b.platform)) \(b.marketingVersion)"
            if let i = out.firstIndex(where: { $0.id == key }) { out[i].builds.append(b) }
            else { out.append(BuildGroup(id: key, builds: [b])) }
        }
        return out
    }

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if let u = store.betaUsage[app.id] {
                Section {
                    BetaUsageTiles(usage: u, loading: false)
                } header: { Text("TestFlight-gebruik") }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section {
                Toggle("Verlopen builds tonen", isOn: $showExpired)
                NavigationLink { BetaGroupsView(app: app) } label: { Label("Testgroepen & testers", systemImage: "person.3.fill") }
            }
            .cardRows()
            ForEach(groups) { group in
                Section(group.id) {
                    ForEach(group.builds) { b in
                        NavigationLink { BuildDetailView(app: app, buildID: b.id) } label: { BuildRow(build: b, installs: store.buildUsage[b.id]?.installs) }
                            .swipeActions(edge: .trailing) {
                                if !b.expired {
                                    Button(role: .destructive) { expireTarget = b } label: { Label("Laat verlopen", systemImage: "clock.badge.xmark") }
                                }
                            }
                    }
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay { if loading && builds.isEmpty { ProgressView() } }
        .navigationTitle("Builds")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Build laten verlopen?", isPresented: Binding(get: { expireTarget != nil }, set: { if !$0 { expireTarget = nil } }), titleVisibility: .visible) {
            if let b = expireTarget {
                Button("Build \(b.number) laten verlopen", role: .destructive) { Task { await expire(b) } }
            }
        } message: { Text("Testers kunnen deze build daarna niet meer installeren. Dit kan niet ongedaan gemaakt worden.") }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do { builds = try await api.builds(appID: app.id, limit: 200); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func expire(_ b: BuildInfo) async {
        guard let api = store.api else { return }
        do { try await api.expireBuild(b.id); feedback = L("Build \(b.number) is verlopen"); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct BuildDetailView: View {
    let app: AppSummary
    let buildID: String
    @Environment(DevStore.self) private var store

    @State private var build: BuildInfo?
    @State private var locs: [Resource<BetaBuildLocalizationAttributes>] = []
    @State private var whatToTest: [String: String] = [:]
    @State private var groups: [Resource<BetaGroupAttributes>] = []
    @State private var memberOf: Set<String> = []
    @State private var betaReview: String?
    @State private var loading = true
    @State private var working = false
    @State private var error: String?
    @State private var feedback: String?
    @State private var confirmExpire = false
    @State private var newLocale = ""
    @State private var usage: BetaUsage?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if let b = build {
                Section {
                    HStack(spacing: 14) {
                        AppIconView(url: b.iconURL ?? app.iconURL, size: 56, name: app.name)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(b.title).font(.title3.weight(.bold).monospacedDigit())
                            StateBadge(state: b.displayState)
                        }
                    }
                }
                .listRowBackground(Color.clear)

                Section("Details") {
                    LabeledContent("Platform", value: Platform.label(b.platform))
                    LabeledContent("Geüpload", value: Fmt.date(b.uploaded))
                    if let e = b.expires { LabeledContent(b.expired ? "Verlopen" : "Verloopt", value: Fmt.date(e)) }
                    if !b.minOS.isEmpty { LabeledContent("Min. OS", value: b.minOS) }
                    LabeledContent("Verwerking") { StateBadge(state: b.processingState) }
                    if !b.internalState.isEmpty { LabeledContent("Intern testen") { StateBadge(state: b.internalState) } }
                    if !b.externalState.isEmpty { LabeledContent("Extern testen") { StateBadge(state: b.externalState) } }
                    if let betaReview { LabeledContent("Beta-review") { StateBadge(state: betaReview) } }
                }
                .cardRows()

                if let u = usage ?? store.buildUsage[b.id] {
                    Section {
                        LabeledContent { Text(Fmt.number(u.installs)).monospacedDigit() } label: { Label("Installaties", systemImage: "arrow.down.circle.fill") }
                        LabeledContent { Text(Fmt.number(u.sessions)).monospacedDigit() } label: { Label("Sessies", systemImage: "play.circle.fill") }
                        LabeledContent { Text(Fmt.number(u.crashes)).monospacedDigit().foregroundStyle(u.crashes > 0 ? Theme.rejected : Theme.textSecondary) } label: { Label("Crashes", systemImage: "exclamationmark.triangle.fill") }
                        LabeledContent { Text(Fmt.number(u.feedback)).monospacedDigit() } label: { Label("Feedback", systemImage: "bubble.left.fill") }
                        LabeledContent { Text(Fmt.number(u.invites)).monospacedDigit() } label: { Label("Uitnodigingen", systemImage: "envelope.fill") }
                    } header: { Text("TestFlight-gebruik") }
                    .cardRows()
                }

                if b.needsCompliance || b.usesNonExemptEncryption == nil {
                    Section {
                        Text("Gebruikt deze build encryptie die niet is vrijgesteld (bijv. eigen crypto, niet alleen HTTPS)?").font(.footnote)
                        Button { Task { await setCompliance(false) } } label: { Label("Nee, alleen vrijgestelde encryptie", systemImage: "checkmark.shield") }
                        Button { Task { await setCompliance(true) } } label: { Label("Ja, gebruikt niet-vrijgestelde encryptie", systemImage: "lock.shield") }
                    } header: { Text("Export compliance") }
                    .cardRows()
                }

                if b.isUsable {
                    Section {
                        if let detail = b.betaDetailID {
                            Toggle("Testers automatisch informeren", isOn: Binding(
                                get: { build?.autoNotify ?? true },
                                set: { v in Task { await setAutoNotify(detail, v) } }
                            ))
                        }
                        Button { Task { await submitBeta() } } label: { Label("Indienen voor beta-review (extern)", systemImage: "paperplane") }
                            .disabled(working || betaReview == "WAITING_FOR_REVIEW" || betaReview == "IN_REVIEW" || betaReview == "APPROVED")
                    } header: { Text("Externe tests") } footer: {
                        Text("Voor externe testgroepen keurt Apple de eerste build van een versie eerst goed.")
                    }
                    .cardRows()
                }

                Section {
                    ForEach(locs) { loc in
                        let code = loc.attributes.locale ?? ""
                        VStack(alignment: .leading, spacing: 8) {
                            LimitedTextEditor(title: "\(Locales.flag(code)) \(Locales.name(code))", text: Binding(
                                get: { whatToTest[loc.id] ?? "" },
                                set: { whatToTest[loc.id] = $0 }
                            ), limit: 4000, minHeight: 90)
                            Button {
                                Task { await saveWhatToTest(loc.id, code) }
                            } label: { Label("Opslaan", systemImage: "checkmark.circle") }
                                .disabled(working || (whatToTest[loc.id] ?? "") == (loc.attributes.whatsNew ?? ""))
                        }
                    }
                    if locs.isEmpty && !loading {
                        Menu {
                            ForEach(Locales.common, id: \.self) { code in
                                Button("\(Locales.flag(code)) \(Locales.name(code))") { Task { await addWhatToTest(code) } }
                            }
                        } label: { Label("What to Test toevoegen", systemImage: "plus.circle") }
                    }
                } header: { Text("Wat te testen") }
                .cardRows()

                Section {
                    if groups.isEmpty && !loading { Text("Geen testgroepen. Maak er een aan via Testgroepen.").font(.footnote).foregroundStyle(Theme.textSecondary) }
                    ForEach(groups) { g in
                        Toggle(isOn: Binding(
                            get: { memberOf.contains(g.id) || (g.attributes.hasAccessToAllBuilds ?? false) },
                            set: { on in Task { await toggleGroup(g, on) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(g.attributes.name ?? "Groep")
                                Text((g.attributes.isInternalGroup ?? false) ? "Intern" : "Extern").font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .disabled(working || !b.isUsable || (g.attributes.hasAccessToAllBuilds ?? false))
                    }
                } header: { Text("Testgroepen") } footer: {
                    Text("Interne groepen met toegang tot alle builds krijgen elke build automatisch.")
                }
                .cardRows()

                if !b.expired {
                    Section {
                        Button(role: .destructive) { confirmExpire = true } label: { Label("Build laten verlopen", systemImage: "clock.badge.xmark") }
                    }
                    .cardRows()
                }
            }
        }
        .themedList()
        .overlay { if loading && build == nil { ProgressView() } }
        .navigationTitle(build?.title ?? "Build")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Build laten verlopen?", isPresented: $confirmExpire, titleVisibility: .visible) {
            Button("Laat verlopen", role: .destructive) { Task { await expire() } }
        }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api, !buildID.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            async let b = api.build(buildID)
            async let l = api.betaLocalizations(buildID: buildID)
            async let g = api.betaGroups(appID: app.id)
            async let m = api.groupIDs(forBuild: buildID)
            async let r = api.betaReviewState(buildID: buildID)
            async let u = api.betaUsage(buildID: buildID)
            build = try await b
            locs = (try? await l) ?? []
            groups = (try? await g) ?? []
            memberOf = (try? await m) ?? []
            betaReview = (try? await r) ?? nil
            usage = try? await u
            for loc in locs { whatToTest[loc.id] = loc.attributes.whatsNew ?? "" }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func perform(_ success: String, _ op: () async throws -> Void) async {
        working = true
        defer { working = false }
        do {
            try await op()
            feedback = success
            error = nil
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func setCompliance(_ value: Bool) async {
        guard let api = store.api else { return }
        await perform("Export compliance opgeslagen") { try await api.setEncryption(buildID: buildID, usesNonExempt: value) }
        await store.reloadApp(app.id)
    }

    private func setAutoNotify(_ detail: String, _ value: Bool) async {
        guard let api = store.api else { return }
        await perform(value ? "Testers worden automatisch geïnformeerd" : "Automatisch informeren uit") { try await api.setAutoNotify(detailID: detail, enabled: value) }
    }

    private func submitBeta() async {
        guard let api = store.api else { return }
        await perform("Ingediend voor beta-review") { try await api.submitForBetaReview(buildID: buildID) }
    }

    private func saveWhatToTest(_ locID: String, _ code: String) async {
        guard let api = store.api else { return }
        let text = whatToTest[locID] ?? ""
        await perform("What to Test opgeslagen") { try await api.saveWhatToTest(buildID: buildID, localizationID: locID, locale: code, text: text) }
    }

    private func addWhatToTest(_ code: String) async {
        guard let api = store.api else { return }
        await perform(L("\(Locales.name(code)) toegevoegd")) { try await api.saveWhatToTest(buildID: buildID, localizationID: nil, locale: code, text: "") }
    }

    private func toggleGroup(_ g: Resource<BetaGroupAttributes>, _ on: Bool) async {
        guard let api = store.api else { return }
        let name = g.attributes.name ?? "groep"
        await perform(on ? L("Toegevoegd aan \(name)") : L("Verwijderd uit \(name)")) {
            if on { try await api.addBuild(buildID, toGroup: g.id) } else { try await api.removeBuild(buildID, fromGroup: g.id) }
        }
    }

    private func expire() async {
        guard let api = store.api else { return }
        await perform("Build is verlopen") { try await api.expireBuild(buildID) }
        await store.reloadApp(app.id)
    }
}

// MARK: - Beta groups

struct BetaGroupsView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var groups: [Resource<BetaGroupAttributes>] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showNew = false
    @State private var newName = ""
    @State private var newInternal = false

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            let internalGroups = groups.filter { $0.attributes.isInternalGroup ?? false }
            let externalGroups = groups.filter { !($0.attributes.isInternalGroup ?? false) }
            if !internalGroups.isEmpty {
                Section("Intern") { ForEach(internalGroups) { row($0) } }.cardRows()
            }
            if !externalGroups.isEmpty {
                Section("Extern") { ForEach(externalGroups) { row($0) } }.cardRows()
            }
            if groups.isEmpty && !loading {
                ContentUnavailableView("Geen testgroepen", systemImage: "person.3", description: Text("Maak een interne of externe testgroep aan."))
                    .listRowBackground(Color.clear)
            }
        }
        .themedList()
        .overlay { if loading && groups.isEmpty { ProgressView() } }
        .navigationTitle("Testgroepen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") } } }
        .task { await load() }
        .refreshable { await load() }
        .alert("Nieuwe testgroep", isPresented: $showNew) {
            TextField("Naam", text: $newName)
            Button("Intern") { newInternal = true; Task { await create() } }
            Button("Extern") { newInternal = false; Task { await create() } }
            Button("Annuleer", role: .cancel) { newName = "" }
        } message: { Text("Interne testers zijn leden van je team; externe testers nodig je uit per e-mail of publieke link.") }
    }

    private func row(_ g: Resource<BetaGroupAttributes>) -> some View {
        NavigationLink { BetaGroupDetailView(app: app, group: g) { await load() } } label: {
            HStack {
                Image(systemName: (g.attributes.isInternalGroup ?? false) ? "person.2.badge.key.fill" : "person.3.fill")
                    .foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.attributes.name ?? "Groep").font(.subheadline.weight(.semibold))
                    if g.attributes.publicLinkEnabled == true { Text("Publieke link actief").font(.caption2).foregroundStyle(Theme.live) }
                }
            }
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do { groups = try await api.betaGroups(appID: app.id); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func create() async {
        guard let api = store.api, !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            try await api.createBetaGroup(appID: app.id, name: newName, isInternal: newInternal)
            newName = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct BetaGroupDetailView: View {
    let app: AppSummary
    @State var group: Resource<BetaGroupAttributes>
    var onChange: () async -> Void

    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var testers: [Resource<BetaTesterAttributes>] = []
    @State private var loading = true
    @State private var error: String?
    @State private var feedback: String?
    @State private var showAdd = false
    @State private var email = ""
    @State private var first = ""
    @State private var last = ""
    @State private var publicLink = false
    @State private var confirmDelete = false

    init(app: AppSummary, group: Resource<BetaGroupAttributes>, onChange: @escaping () async -> Void) {
        self.app = app
        _group = State(initialValue: group)
        self.onChange = onChange
    }

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if !(group.attributes.isInternalGroup ?? false) {
                Section {
                    Toggle("Publieke link", isOn: Binding(get: { publicLink }, set: { v in Task { await setPublic(v) } }))
                    if publicLink, let link = group.attributes.publicLink, let url = URL(string: link) {
                        ShareLink(item: url) { Label(link, systemImage: "link").lineLimit(1) }
                    }
                } header: { Text("Uitnodigen") }
                .cardRows()
            }
            Section {
                ForEach(testers) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.attributes.displayName).font(.subheadline.weight(.medium))
                        HStack(spacing: 6) {
                            if let mail = t.attributes.email { Text(mail) }
                            if let state = t.attributes.state { Text("· \(state.replacingOccurrences(of: "_", with: " ").lowercased())") }
                        }
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await remove(t) } } label: { Label("Verwijder", systemImage: "person.badge.minus") }
                    }
                }
                Button { showAdd = true } label: { Label("Tester toevoegen", systemImage: "person.badge.plus") }
            } header: { Text("Testers (\(testers.count))") }
            .cardRows()
            Section {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Groep verwijderen", systemImage: "trash") }
            }
            .cardRows()
        }
        .themedList()
        .overlay { if loading && testers.isEmpty { ProgressView() } }
        .navigationTitle(group.attributes.name ?? "Groep")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            publicLink = group.attributes.publicLinkEnabled ?? false
            await load()
        }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField("E-mailadres", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Voornaam", text: $first)
                    TextField("Achternaam", text: $last)
                }
                .navigationTitle("Tester toevoegen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { showAdd = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Uitnodigen") { Task { await add() } }.disabled(!email.contains("@")) }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Groep verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) { Task { await deleteGroup() } }
        }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do { testers = try await api.testers(groupID: group.id); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func add() async {
        guard let api = store.api else { return }
        do {
            try await api.addTester(groupID: group.id, email: email, firstName: first, lastName: last)
            showAdd = false
            feedback = L("Uitnodiging verstuurd naar \(email)")
            email = ""; first = ""; last = ""
            await load()
        } catch { self.error = error.localizedDescription; showAdd = false }
    }

    private func remove(_ t: Resource<BetaTesterAttributes>) async {
        guard let api = store.api else { return }
        do { try await api.removeTester(t.id, fromGroup: group.id); feedback = "Tester verwijderd"; await load() }
        catch { self.error = error.localizedDescription }
    }

    private func setPublic(_ on: Bool) async {
        guard let api = store.api else { return }
        do {
            try await api.setPublicLink(groupID: group.id, enabled: on)
            publicLink = on
            let groups = try await api.betaGroups(appID: app.id)
            if let g = groups.first(where: { $0.id == group.id }) { group = g }
        } catch { self.error = error.localizedDescription }
    }

    private func deleteGroup() async {
        guard let api = store.api else { return }
        do { try await api.deleteBetaGroup(group.id); await onChange(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - TestFlight usage components

/// Four tiles: installs, testers, sessions and crashes.
struct BetaUsageTiles: View {
    let usage: BetaUsage
    var loading = false
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            StatTile(title: "TestFlight-installaties", value: loading ? "…" : Fmt.number(usage.installs), systemImage: "arrow.down.circle.fill", tint: Theme.cyan)
            StatTile(title: "Testers", value: loading ? "…" : usage.testers.map { Fmt.number($0) } ?? "—", systemImage: "person.2.fill", tint: Theme.accent,
                     footnote: loading ? nil : L("\(Fmt.number(usage.invites)) uitnodigingen"))
            StatTile(title: "Sessies", value: loading ? "…" : Fmt.number(usage.sessions), systemImage: "play.circle.fill", tint: Theme.live)
            StatTile(title: "Crashes", value: loading ? "…" : Fmt.number(usage.crashes), systemImage: "exclamationmark.triangle.fill",
                     tint: usage.crashes > 0 ? Theme.rejected : Theme.textSecondary,
                     footnote: loading ? nil : L("\(Fmt.number(usage.feedback)) feedback"))
        }
    }
}

/// Small "↓ 123" capsule for lists.
struct InstallCount: View {
    let value: Int
    var body: some View {
        Label(Fmt.number(value), systemImage: "arrow.down.circle.fill")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.cyan)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(L("\(Fmt.number(value)) TestFlight-installaties"))
    }
}

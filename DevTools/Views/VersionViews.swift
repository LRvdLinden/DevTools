import SwiftUI

enum Locales {
    static let common = ["en-US", "en-GB", "nl-NL", "de-DE", "fr-FR", "es-ES", "it", "pt-PT", "pt-BR", "sv", "da", "no", "fi", "pl",
                         "ja", "ko", "zh-Hans", "zh-Hant", "tr", "ru", "en-AU", "en-CA", "fr-CA", "es-MX"]
    static func name(_ id: String) -> String {
        Locale.current.localizedString(forIdentifier: id)?.capitalized ?? id
    }
    static func flag(_ id: String) -> String {
        let parts = id.split(separator: "-")
        if parts.count > 1, parts[1].count == 2 { return Fmt.flag(String(parts[1])) }
        switch id {
        case "nl": return Fmt.flag("NL")
        case "de": return Fmt.flag("DE")
        case "fr": return Fmt.flag("FR")
        case "it": return Fmt.flag("IT")
        case "sv": return Fmt.flag("SE")
        case "da": return Fmt.flag("DK")
        case "no": return Fmt.flag("NO")
        case "fi": return Fmt.flag("FI")
        case "pl": return Fmt.flag("PL")
        case "ja": return Fmt.flag("JP")
        case "ko": return Fmt.flag("KR")
        case "tr": return Fmt.flag("TR")
        case "ru": return Fmt.flag("RU")
        case "zh-Hans": return Fmt.flag("CN")
        case "zh-Hant": return Fmt.flag("TW")
        default: return "🌐"
        }
    }
}

// MARK: - Version detail

struct VersionDetailView: View {
    let appID: String
    @State var version: VersionInfo
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var localizations: [Resource<VersionLocalizationAttributes>] = []
    @State private var build: BuildInfo?
    @State private var loading = true
    @State private var error: String?
    @State private var feedback: String?
    @State private var working = false

    @State private var versionString = ""
    @State private var copyright = ""
    @State private var releaseType = "AFTER_APPROVAL"
    @State private var scheduled = Date().addingTimeInterval(86_400 * 2)

    @State private var showBuildPicker = false
    @State private var confirmSubmit = false
    @State private var confirmCancel = false
    @State private var confirmRelease = false
    @State private var confirmDelete = false

    init(appID: String, version: VersionInfo) {
        self.appID = appID
        _version = State(initialValue: version)
    }

    private var app: AppSummary? { store.apps.first { $0.id == appID } }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AppIconView(url: app?.iconURL, size: 54, name: app?.name ?? "")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(version.platformLabel) \(version.versionString)").font(.title3.weight(.bold))
                        StateBadge(state: version.state)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

            if let error { Section { ErrorBanner(message: error) }.listRowBackground(Color.clear) }

            actionsSection

            Section {
                if let build {
                    BuildRow(build: build)
                } else {
                    Text(loading ? "Laden…" : "Nog geen build gekozen").foregroundStyle(Theme.textSecondary)
                }
                if version.isEditable {
                    Button { showBuildPicker = true } label: { Label(build == nil ? "Kies build" : "Andere build kiezen", systemImage: "hammer") }
                }
            } header: { Text("Build") } footer: {
                Text("Builds upload je vanuit Xcode of Transporter. Hier koppel je een verwerkte build aan deze versie.")
            }
            .cardRows()

            Section("Versie-instellingen") {
                if version.state == "PREPARE_FOR_SUBMISSION" {
                    TextField("Versienummer", text: $versionString).keyboardType(.decimalPad)
                } else {
                    LabeledContent("Versienummer", value: version.versionString)
                }
                TextField("Copyright, bijv. 2026 PixelForges", text: $copyright)
                Picker("Vrijgave", selection: $releaseType) {
                    ForEach(ReleaseType.all, id: \.self) { Text(ReleaseType.label($0)).tag($0) }
                }
                if releaseType == "SCHEDULED" {
                    DatePicker("Datum", selection: $scheduled, in: Date()...)
                }
                Button {
                    Task { await saveSettings() }
                } label: { Label("Instellingen opslaan", systemImage: "checkmark.circle") }
                .disabled(working || !version.isEditable && version.state != "PENDING_DEVELOPER_RELEASE")
            }
            .cardRows()

            Section {
                ForEach(localizations) { loc in
                    NavigationLink {
                        LocalizationEditorView(localization: loc, all: localizations, editable: version.isEditable) { await load() }
                    } label: {
                        HStack(spacing: 10) {
                            Text(Locales.flag(loc.attributes.locale ?? "")).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Locales.name(loc.attributes.locale ?? "")).font(.subheadline.weight(.medium))
                                Text(preview(loc)).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                        }
                    }
                }
                if version.isEditable {
                    Menu {
                        ForEach(Locales.common.filter { code in !localizations.contains { $0.attributes.locale == code } }, id: \.self) { code in
                            Button("\(Locales.flag(code)) \(Locales.name(code))") { Task { await addLocale(code) } }
                        }
                    } label: { Label("Taal toevoegen", systemImage: "plus.circle") }
                }
            } header: { Text("Teksten per taal") } footer: {
                Text("What's New, beschrijving, keywords en promotietekst. Promotietekst kun je ook wijzigen als de versie live is.")
            }
            .cardRows()

            if version.state == "PREPARE_FOR_SUBMISSION" {
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Versie verwijderen", systemImage: "trash") }
                }
                .cardRows()
            }
        }
        .themedList()
        .navigationTitle(version.versionString)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if working { ProgressView().controlSize(.large).padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showBuildPicker) {
            BuildPickerSheet(appID: appID, platform: version.platform, preferredVersion: version.versionString) { b in
                Task { await attach(b) }
            }
        }
        .confirmationDialog("Indienen voor App Review?", isPresented: $confirmSubmit, titleVisibility: .visible) {
            Button("Indienen") { Task { await submit() } }
        } message: { Text("Versie \(version.versionString) met build \(build?.number ?? "?") gaat naar App Review.") }
        .confirmationDialog("Review annuleren?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Review annuleren", role: .destructive) { Task { await cancelReview() } }
        } message: { Text("De versie wordt teruggetrokken uit App Review. Je kunt hem daarna opnieuw indienen.") }
        .confirmationDialog("Nu vrijgeven?", isPresented: $confirmRelease, titleVisibility: .visible) {
            Button("Vrijgeven in de App Store") { Task { await release() } }
        } message: { Text("Versie \(version.versionString) wordt direct beschikbaar voor gebruikers.") }
        .confirmationDialog("Versie verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) { Task { await deleteVersion() } }
        }
        .actionFeedback($feedback)
    }

    @ViewBuilder
    private var actionsSection: some View {
        let state = version.state
        if version.isEditable || state == "WAITING_FOR_REVIEW" || state == "IN_REVIEW" || state == "PENDING_DEVELOPER_RELEASE" {
            Section("Acties") {
                if ["PREPARE_FOR_SUBMISSION", "REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "INVALID_BINARY"].contains(state) {
                    Button { confirmSubmit = true } label: {
                        Label("Indienen voor review", systemImage: "paperplane.fill").font(.headline)
                    }
                    .disabled(build == nil || working)
                    if build == nil { Text("Kies eerst een build.").font(.caption).foregroundStyle(Theme.textSecondary) }
                }
                if state == "WAITING_FOR_REVIEW" || state == "IN_REVIEW" {
                    Button(role: .destructive) { confirmCancel = true } label: { Label("Review annuleren", systemImage: "xmark.circle") }
                }
                if state == "PENDING_DEVELOPER_RELEASE" {
                    Button { confirmRelease = true } label: { Label("Nu vrijgeven", systemImage: "sparkles").font(.headline) }
                        .tint(Theme.live)
                }
            }
            .cardRows()
        }
    }

    private func preview(_ loc: Resource<VersionLocalizationAttributes>) -> String {
        let a = loc.attributes
        let text = (a.whatsNew?.isEmpty == false ? a.whatsNew : a.description) ?? ""
        return text.isEmpty ? "Nog geen tekst" : text.replacingOccurrences(of: "\n", with: " ")
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do {
            async let v = api.version(version.id)
            async let locs = api.versionLocalizations(versionID: version.id)
            async let b = api.versionBuild(versionID: version.id)
            let fresh = try await v
            version = fresh
            localizations = try await locs
            build = try? await b
            versionString = fresh.versionString
            copyright = fresh.copyright
            releaseType = fresh.releaseType
            if let d = fresh.earliestRelease { scheduled = d }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func run(_ success: String, _ op: () async throws -> Void) async {
        working = true
        defer { working = false }
        do {
            try await op()
            feedback = success
            error = nil
            await load()
            await store.reloadApp(appID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveSettings() async {
        guard let api = store.api else { return }
        var attrs: [String: Any] = ["copyright": copyright, "releaseType": releaseType]
        if version.state == "PREPARE_FOR_SUBMISSION", versionString != version.versionString, !versionString.isEmpty { attrs["versionString"] = versionString }
        if releaseType == "SCHEDULED" { attrs["earliestReleaseDate"] = ASCDate.iso(scheduled) }
        await run("Instellingen opgeslagen") { try await api.updateVersion(version.id, attributes: attrs) }
    }

    private func attach(_ b: BuildInfo) async {
        guard let api = store.api else { return }
        await run("Build \(b.number) gekoppeld") { try await api.setVersionBuild(versionID: version.id, buildID: b.id) }
    }

    private func submit() async {
        guard let api = store.api else { return }
        await run("Ingediend voor review 🚀") { try await api.submitForReview(appID: appID, versionID: version.id, platform: version.platform) }
    }

    private func cancelReview() async {
        guard let api = store.api else { return }
        await run("Review geannuleerd") { try await api.cancelReview(appID: appID, platform: version.platform) }
    }

    private func release() async {
        guard let api = store.api else { return }
        await run("Versie vrijgegeven 🎉") { try await api.releaseVersion(versionID: version.id) }
    }

    private func addLocale(_ code: String) async {
        guard let api = store.api else { return }
        await run("\(Locales.name(code)) toegevoegd") { try await api.createVersionLocalization(versionID: version.id, locale: code, attributes: [:]) }
    }

    private func deleteVersion() async {
        guard let api = store.api else { return }
        working = true
        defer { working = false }
        do {
            try await api.deleteVersion(version.id)
            await store.reloadApp(appID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Localization editor

struct LocalizationEditorView: View {
    let localization: Resource<VersionLocalizationAttributes>
    let all: [Resource<VersionLocalizationAttributes>]
    let editable: Bool
    var onSaved: () async -> Void

    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var whatsNew = ""
    @State private var promo = ""
    @State private var description = ""
    @State private var keywords = ""
    @State private var support = ""
    @State private var marketing = ""
    @State private var saving = false
    @State private var error: String?
    @State private var feedback: String?

    var body: some View {
        Form {
            if let error { Section { ErrorBanner(message: error) }.listRowBackground(Color.clear) }
            Section {
                LimitedTextEditor(title: "Nieuw in deze versie (What's New)", text: $whatsNew, limit: 4000, minHeight: 120)
                    .disabled(!editable)
                if editable && all.count > 1 {
                    Button { Task { await copyWhatsNewToAll() } } label: {
                        Label("Kopieer naar alle \(all.count - 1) andere talen", systemImage: "doc.on.doc")
                    }
                    .disabled(whatsNew.isEmpty || saving)
                }
            }
            .cardRows()
            Section {
                LimitedTextEditor(title: "Promotietekst", text: $promo, limit: 170, minHeight: 60)
            } footer: { Text("Kan altijd aangepast worden, ook zonder nieuwe versie.") }
            .cardRows()
            Section {
                LimitedTextEditor(title: "Beschrijving", text: $description, limit: 4000, minHeight: 180)
                    .disabled(!editable)
                LimitedTextEditor(title: "Trefwoorden (komma-gescheiden)", text: $keywords, limit: 100, singleLine: true)
                    .disabled(!editable)
            }
            .cardRows()
            Section("Links") {
                TextField("Support-URL", text: $support).keyboardType(.URL).textInputAutocapitalization(.never).disabled(!editable)
                TextField("Marketing-URL", text: $marketing).keyboardType(.URL).textInputAutocapitalization(.never).disabled(!editable)
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("\(Locales.flag(localization.attributes.locale ?? "")) \(Locales.name(localization.attributes.locale ?? ""))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else { Button("Opslaan") { Task { await save() } }.fontWeight(.semibold) }
            }
        }
        .onAppear(perform: fill)
        .actionFeedback($feedback)
    }

    private func fill() {
        let a = localization.attributes
        whatsNew = a.whatsNew ?? ""
        promo = a.promotionalText ?? ""
        description = a.description ?? ""
        keywords = a.keywords ?? ""
        support = a.supportUrl ?? ""
        marketing = a.marketingUrl ?? ""
    }

    private func changes() -> [String: Any] {
        let a = localization.attributes
        var attrs: [String: Any] = [:]
        if promo != (a.promotionalText ?? "") { attrs["promotionalText"] = promo }
        if editable {
            if whatsNew != (a.whatsNew ?? "") { attrs["whatsNew"] = whatsNew }
            if description != (a.description ?? "") { attrs["description"] = description }
            if keywords != (a.keywords ?? "") { attrs["keywords"] = keywords }
            if support != (a.supportUrl ?? "") { attrs["supportUrl"] = support }
            if marketing != (a.marketingUrl ?? "") { attrs["marketingUrl"] = marketing.isEmpty ? (NSNull() as Any) : (marketing as Any) }
        }
        return attrs
    }

    private func save() async {
        guard let api = store.api else { return }
        let attrs = changes()
        guard !attrs.isEmpty else { dismiss(); return }
        saving = true
        defer { saving = false }
        do {
            try await api.updateVersionLocalization(localization.id, attributes: attrs)
            await onSaved()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func copyWhatsNewToAll() async {
        guard let api = store.api else { return }
        saving = true
        defer { saving = false }
        var failed: [String] = []
        for loc in all {
            do { try await api.updateVersionLocalization(loc.id, attributes: ["whatsNew": whatsNew]) }
            catch { failed.append(loc.attributes.locale ?? loc.id) }
        }
        if failed.isEmpty { feedback = "What's New in \(all.count) talen gezet" }
        else { error = "Niet gelukt voor: \(failed.joined(separator: ", "))" }
        await onSaved()
    }
}

// MARK: - Create version

struct CreateVersionSheet: View {
    let app: AppSummary
    var onCreated: (VersionInfo) -> Void

    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var platform = "IOS"
    @State private var versionString = ""
    @State private var releaseType = "AFTER_APPROVAL"
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Platform", selection: $platform) {
                        ForEach(platformOptions, id: \.self) { Label(Platform.label($0), systemImage: Platform.icon($0)).tag($0) }
                    }
                    TextField("Versienummer", text: $versionString)
                        .keyboardType(.decimalPad)
                        .font(.title3.monospacedDigit())
                    Picker("Vrijgave", selection: $releaseType) {
                        ForEach(ReleaseType.all.filter { $0 != "SCHEDULED" }, id: \.self) { Text(ReleaseType.label($0)).tag($0) }
                    }
                } footer: {
                    Text("Apple neemt de teksten van de vorige versie over. Daarna vul je What's New in, kies je een build en dien je in.")
                }
                .cardRows()
                if let error { Section { ErrorBanner(message: error) }.listRowBackground(Color.clear) }
            }
            .themedList()
            .navigationTitle("Nieuwe versie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else {
                        Button("Maak aan") { Task { await create() } }.fontWeight(.semibold).disabled(versionString.isEmpty)
                    }
                }
            }
            .onAppear {
                platform = app.platforms.first ?? "IOS"
                versionString = suggestion(for: platform)
            }
            .onChange(of: platform) { _, p in versionString = suggestion(for: p) }
        }
        .presentationDetents([.medium, .large])
    }

    private var platformOptions: [String] {
        let known = app.platforms
        return known.isEmpty ? Platform.all : known + Platform.all.filter { !known.contains($0) }
    }

    private func suggestion(for platform: String) -> String {
        guard let last = app.versions.first(where: { $0.platform == platform })?.versionString else { return "1.0.0" }
        var parts = last.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        parts[parts.count - 1] += 1
        return parts.map(String.init).joined(separator: ".")
    }

    private func create() async {
        guard let api = store.api else { return }
        working = true
        defer { working = false }
        do {
            let v = try await api.createVersion(appID: app.id, platform: platform, versionString: versionString, releaseType: releaseType)
            await store.reloadApp(app.id)
            dismiss()
            onCreated(v)
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Build picker

struct BuildPickerSheet: View {
    let appID: String
    let platform: String
    var preferredVersion: String = ""
    var onPick: (BuildInfo) -> Void

    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var builds: [BuildInfo] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
                let usable = builds.filter { $0.isUsable && ($0.platform == platform || $0.platform.isEmpty) }
                if usable.isEmpty && !loading {
                    ContentUnavailableView("Geen bruikbare builds", systemImage: "hammer", description: Text("Upload een build vanuit Xcode; na verwerking verschijnt hij hier."))
                        .listRowBackground(Color.clear)
                }
                ForEach(usable) { b in
                    Button {
                        onPick(b)
                        dismiss()
                    } label: {
                        HStack {
                            BuildRow(build: b)
                            if b.marketingVersion == preferredVersion { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .cardRows()
            }
            .themedList()
            .overlay { if loading { ProgressView() } }
            .navigationTitle("Kies build")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } } }
            .task {
                guard let api = store.api else { return }
                do { builds = try await api.builds(appID: appID, limit: 50) } catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }
}

// MARK: - App info (name, subtitle, privacy URL)

struct InfoDraft {
    var name = ""
    var subtitle = ""
    var privacy = ""
}

struct AppInfoEditorView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var infoState = ""
    @State private var locs: [Resource<AppInfoLocalizationAttributes>] = []
    @State private var drafts: [String: InfoDraft] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var feedback: String?
    @State private var savingID: String?

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if !infoState.isEmpty {
                Section { LabeledContent("Status") { StateBadge(state: infoState) } }.cardRows()
            }
            ForEach(locs) { loc in
                Section {
                    LimitedTextEditor(title: "Naam", text: binding(loc.id, \.name), limit: 30, singleLine: true)
                    LimitedTextEditor(title: "Ondertitel", text: binding(loc.id, \.subtitle), limit: 30, singleLine: true)
                    TextField("Privacybeleid-URL", text: binding(loc.id, \.privacy))
                        .keyboardType(.URL).textInputAutocapitalization(.never).font(.callout)
                    Button {
                        Task { await save(loc) }
                    } label: {
                        if savingID == loc.id { ProgressView() } else { Label("Opslaan", systemImage: "checkmark.circle") }
                    }
                } header: {
                    Text("\(Locales.flag(loc.attributes.locale ?? "")) \(Locales.name(loc.attributes.locale ?? ""))")
                }
                .cardRows()
            }
        }
        .themedList()
        .overlay { if loading { ProgressView() } }
        .navigationTitle("App-informatie")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .actionFeedback($feedback)
    }

    private func binding(_ id: String, _ key: WritableKeyPath<InfoDraft, String>) -> Binding<String> {
        Binding(
            get: { drafts[id]?[keyPath: key] ?? "" },
            set: { newValue in
                var d = drafts[id] ?? InfoDraft()
                d[keyPath: key] = newValue
                drafts[id] = d
            }
        )
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do {
            guard let info = try await api.editableAppInfo(appID: app.id) else { error = "Geen app-informatie gevonden"; return }
            infoState = info.state
            locs = try await api.appInfoLocalizations(infoID: info.id)
            for l in locs {
                drafts[l.id] = InfoDraft(name: l.attributes.name ?? "", subtitle: l.attributes.subtitle ?? "", privacy: l.attributes.privacyPolicyUrl ?? "")
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save(_ loc: Resource<AppInfoLocalizationAttributes>) async {
        guard let api = store.api, let d = drafts[loc.id] else { return }
        savingID = loc.id
        defer { savingID = nil }
        var attrs: [String: Any] = [:]
        if d.name != (loc.attributes.name ?? "") { attrs["name"] = d.name }
        if d.subtitle != (loc.attributes.subtitle ?? "") { attrs["subtitle"] = d.subtitle }
        if d.privacy != (loc.attributes.privacyPolicyUrl ?? "") { attrs["privacyPolicyUrl"] = d.privacy }
        guard !attrs.isEmpty else { feedback = "Geen wijzigingen"; return }
        do {
            try await api.updateAppInfoLocalization(loc.id, attributes: attrs)
            feedback = "Opgeslagen"
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

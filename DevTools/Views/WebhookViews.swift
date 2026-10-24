import SwiftUI

// MARK: - App Store Connect webhooks + DevTools push notifications

enum WebhookEvents {
    static let main: [(String, String)] = [
        ("APP_STORE_VERSION_APP_VERSION_STATE_UPDATED", "Status van een App Store-versie"),
        ("BUILD_UPLOAD_STATE_UPDATED", "Build geüpload of verwerkt"),
        ("BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED", "Status externe TestFlight"),
        ("BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED", "Nieuwe TestFlight-feedback"),
        ("BETA_FEEDBACK_CRASH_SUBMISSION_CREATED", "Nieuwe TestFlight-crash"),
    ]
    static let other: [(String, String)] = [
        ("BACKGROUND_ASSET_VERSION_STATE_UPDATED", "Background Assets: status"),
        ("BACKGROUND_ASSET_VERSION_APP_STORE_RELEASE_STATE_UPDATED", "Background Assets: App Store-release"),
        ("BACKGROUND_ASSET_VERSION_EXTERNAL_BETA_RELEASE_STATE_UPDATED", "Background Assets: externe beta"),
        ("BACKGROUND_ASSET_VERSION_INTERNAL_BETA_RELEASE_CREATED", "Background Assets: interne beta"),
        ("ALTERNATIVE_DISTRIBUTION_PACKAGE_AVAILABLE_UPDATED", "Alternatieve distributie: pakket beschikbaar"),
        ("ALTERNATIVE_DISTRIBUTION_PACKAGE_VERSION_CREATED", "Alternatieve distributie: nieuwe pakketversie"),
        ("ALTERNATIVE_DISTRIBUTION_TERRITORY_AVAILABILITY_UPDATED", "Alternatieve distributie: landen"),
    ]
    static func label(_ raw: String) -> String { LS((main + other).first { $0.0 == raw }?.1 ?? Pretty.label(raw)) }
    static let pushDefault = main.map(\.0)
    static let pushName = "DevTools push"
}

extension PushManager {
    /// Creates (or updates) the DevTools push webhook for one app. Returns false if push isn't registered.
    func ensureWebhook(api: ConnectAPI, appID: String, appName: String) async throws -> Bool {
        guard let reg = registration else { return false }
        var comps = URLComponents(string: reg.webhookURL)
        comps?.queryItems = [URLQueryItem(name: "app", value: appName),
                             URLQueryItem(name: "lang", value: LanguageManager.locale.language.languageCode?.identifier ?? "en")]
        let url = comps?.url?.absoluteString ?? reg.webhookURL
        let existing = try await api.jget("/v1/apps/\(appID)/webhooks", [("limit", "50")]).data
        if let hook = existing.first(where: { $0.str("name") == WebhookEvents.pushName || $0.str("url").hasPrefix(reg.webhookURL) }) {
            try await api.jpatch("/v1/webhooks/\(hook.id)", type: "webhooks", id: hook.id, attributes: [
                "url": url, "secret": reg.secret, "enabled": true, "eventTypes": WebhookEvents.pushDefault, "name": WebhookEvents.pushName,
            ])
        } else {
            try await api.jcreate("/v1/webhooks", type: "webhooks", attributes: [
                "name": WebhookEvents.pushName, "url": url, "secret": reg.secret, "enabled": true, "eventTypes": WebhookEvents.pushDefault,
            ], relationships: ["app": ("apps", appID)])
        }
        return true
    }

    func removeWebhook(api: ConnectAPI, appID: String) async throws {
        let existing = try await api.jget("/v1/apps/\(appID)/webhooks", [("limit", "50")]).data
        for hook in existing where hook.str("name") == WebhookEvents.pushName || (registration.map { hook.str("url").hasPrefix($0.webhookURL) } ?? false) {
            try await api.jdelete("/v1/webhooks/\(hook.id)")
        }
    }
}

/// Account → Pushmeldingen: register this device and turn push on/off for every app at once.
struct PushSettingsView: View {
    @Environment(DevStore.self) private var store
    @State private var push = PushManager.shared
    @State private var progress: String?
    @State private var feedback: String?
    @State private var error: String?

    var body: some View {
        List {
            if let e = error ?? push.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Meldingen van App Store Connect").font(.subheadline.weight(.semibold))
                        Text("Krijg een pushmelding zodra een versie in review gaat, wordt goedgekeurd, afgewezen of live gaat, als een build klaar is, en bij nieuwe TestFlight-feedback of crashes.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                } icon: { Image(systemName: "bell.badge.fill").foregroundStyle(Theme.accent) }
                if !push.isConfigured {
                    Text("Pushmeldingen zijn in deze build nog niet geactiveerd.").font(.footnote).foregroundStyle(Theme.review)
                } else if push.enabled && push.registration != nil {
                    Label("Deze iPhone is aangemeld", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.live)
                    Button { Task { await allApps(on: true) } } label: { Label("Aanzetten voor al mijn apps", systemImage: "bell.and.waves.left.and.right") }
                        .disabled(progress != nil || store.isDemo)
                    Button(role: .destructive) { Task { await allApps(on: false) } } label: { Label("Uitzetten voor al mijn apps", systemImage: "bell.slash") }
                        .disabled(progress != nil || store.isDemo)
                } else {
                    Button { Task { _ = await push.enable() } } label: { Label("Pushmeldingen inschakelen", systemImage: "bell.fill") }
                        .disabled(push.working)
                }
                if let progress { HStack { ProgressView(); Text(progress).font(.footnote) } }
            } footer: {
                Text("DevTools zet per app een webhook in App Store Connect die naar de DevTools-pushserver wijst. Die controleert Apple's handtekening en stuurt de melding via OneSignal naar dit toestel. Er wordt niets opgeslagen; je API-sleutel verlaat dit toestel niet.")
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Pushmeldingen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await push.refreshAuthorization() }
        .actionFeedback($feedback)
    }

    private func allApps(on: Bool) async {
        guard let api = store.api else { return }
        var done = 0
        for app in store.apps {
            progress = "\(app.name) (\(done + 1)/\(store.apps.count))"
            do {
                if on { _ = try await push.ensureWebhook(api: api, appID: app.id, appName: app.name) }
                else { try await push.removeWebhook(api: api, appID: app.id) }
            } catch { self.error = "\(app.name): \(error.localizedDescription)" }
            done += 1
        }
        progress = nil
        if !on { push.disable() }
        feedback = on ? L("Pushmeldingen staan aan voor \(done) apps") : L("Pushmeldingen uitgezet")
    }
}

/// Webhooks of one app: list, create, toggle, ping, deliveries.
struct WebhooksView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var push = PushManager.shared
    @State private var loader = Loader()
    @State private var showNew = false
    @State private var feedback: String?

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            Section {
                let pushHook = loader.doc.data.first { $0.str("name") == WebhookEvents.pushName }
                if !push.isConfigured {
                    Text("Pushmeldingen zijn in deze build nog niet geactiveerd.").font(.footnote).foregroundStyle(Theme.textSecondary)
                } else if push.registration == nil {
                    NavigationLink { PushSettingsView() } label: { Label("Pushmeldingen instellen", systemImage: "bell.badge") }
                } else if pushHook == nil {
                    Button { Task { await setPush(true) } } label: { Label("Pushmeldingen voor deze app aanzetten", systemImage: "bell.fill") }
                } else {
                    Label("Pushmeldingen staan aan", systemImage: "bell.badge.fill").foregroundStyle(Theme.live)
                    Button(role: .destructive) { Task { await setPush(false) } } label: { Label("Uitzetten", systemImage: "bell.slash") }
                }
            } header: { Text("Pushmeldingen op dit toestel") }
            .cardRows()

            Section {
                ForEach(loader.doc.data) { h in
                    NavigationLink { WebhookDetailView(hook: h) { await load() } } label: {
                        InfoRow(title: h.str("name"), subtitle: h.str("url") + "\n" + L("\(h.strings("eventTypes").count) gebeurtenissen"),
                                icon: "point.3.connected.trianglepath.dotted", tint: h.b("enabled") == false ? Theme.textSecondary : Theme.accent,
                                badge: h.b("enabled") == false ? "DISABLED" : nil)
                    }
                }
                Button { showNew = true } label: { Label("Nieuwe webhook", systemImage: "plus.circle") }
            } header: { Text("Webhooks") } footer: {
                Text("Apple stuurt bij elke gekozen gebeurtenis een ondertekend bericht naar de URL, bijvoorbeeld naar Homey, Slack of je eigen server.")
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Webhooks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNew) { NewWebhookSheet(appID: app.id) { await load() } }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/apps/\(app.id)/webhooks", [("limit", "50")]) }
    }

    private func setPush(_ on: Bool) async {
        guard let api = store.api else { return }
        do {
            if on { _ = try await push.ensureWebhook(api: api, appID: app.id, appName: app.name); feedback = L("Pushmeldingen aan") }
            else { try await push.removeWebhook(api: api, appID: app.id); feedback = L("Pushmeldingen uit") }
            await load()
        } catch { loader.error = error.localizedDescription }
    }
}

struct EventTypePicker: View {
    @Binding var selected: Set<String>
    var body: some View {
        Section("Gebeurtenissen") {
            ForEach(WebhookEvents.main, id: \.0) { e in toggle(e) }
        }
        Section("Overig") {
            ForEach(WebhookEvents.other, id: \.0) { e in toggle(e) }
        }
    }
    private func toggle(_ e: (String, String)) -> some View {
        Toggle(LS(e.1), isOn: Binding(get: { selected.contains(e.0) }, set: { on in if on { selected.insert(e.0) } else { selected.remove(e.0) } }))
            .font(.subheadline)
    }
}

struct NewWebhookSheet: View {
    let appID: String
    var onDone: () async -> Void
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = "https://"
    @State private var secret = Self.randomSecret()
    @State private var events: Set<String> = Set(WebhookEvents.pushDefault)
    @State private var error: String?
    @State private var working = false

    static func randomSecret() -> String {
        (0..<32).map { _ in String("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()!) }.joined()
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(Theme.rejected).font(.footnote) }
                Section {
                    TextField("Naam", text: $name)
                    TextField("URL (https)", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
                    HStack {
                        TextField("Geheim", text: $secret).font(.footnote.monospaced()).textInputAutocapitalization(.never)
                        Button { UIPasteboard.general.string = secret } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                    }
                } footer: { Text("Met het geheim controleert de ontvanger de X-Apple-SIGNATURE-header (HMAC-SHA256). Bewaar het goed; Apple toont het later niet meer.") }
                EventTypePicker(selected: $events)
            }
            .navigationTitle("Nieuwe webhook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Maak aan") { Task { await create() } }.disabled(working || name.isEmpty || !url.hasPrefix("https://") || url.count < 12 || events.isEmpty || secret.count < 8)
                }
            }
        }
    }

    private func create() async {
        guard let api = store.api else { return }
        working = true
        defer { working = false }
        do {
            try await api.jcreate("/v1/webhooks", type: "webhooks",
                                  attributes: ["name": name, "url": url, "secret": secret, "enabled": true, "eventTypes": Array(events)],
                                  relationships: ["app": ("apps", appID)])
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct WebhookDetailView: View {
    let hook: JRes
    var onChange: () async -> Void
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = true
    @State private var events: Set<String> = []
    @State private var deliveries: [JRes] = []
    @State private var included: [JRes] = []
    @State private var error: String?
    @State private var feedback: String?
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            Section {
                LabeledContent("URL", value: hook.str("url")).font(.footnote)
                Toggle("Actief", isOn: $enabled)
                Button { Task { await save() } } label: { Label("Bewaar", systemImage: "checkmark.circle") }
                Button { Task { await ping() } } label: { Label("Stuur testbericht (ping)", systemImage: "dot.radiowaves.left.and.right") }
            }
            .cardRows()
            EventTypePicker(selected: $events).cardRows()
            Section("Laatste afleveringen") {
                ForEach(deliveries.sorted { ($0.date("createdDate") ?? .distantPast) > ($1.date("createdDate") ?? .distantPast) }) { d in
                    let event = included.first { $0.id == d.rel("event") }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.map { $0.b("ping") == true ? L("Ping") : WebhookEvents.label($0.str("eventType")) } ?? L("Gebeurtenis")).font(.subheadline)
                            Text(Fmt.date(d.date("createdDate"))).font(.caption2).foregroundStyle(Theme.textSecondary)
                            if let m = d.s("errorMessage"), !m.isEmpty { Text(m).font(.caption2).foregroundStyle(Theme.rejected) }
                        }
                        Spacer()
                        Text(Pretty.label(d.s("deliveryState"))).font(.caption.weight(.semibold))
                            .foregroundStyle(d.s("deliveryState") == "SUCCEEDED" ? Theme.live : d.s("deliveryState") == "FAILED" ? Theme.rejected : Theme.review)
                    }
                    .swipeActions {
                        if d.s("deliveryState") == "FAILED" {
                            Button { Task { await redeliver(d) } } label: { Label("Opnieuw", systemImage: "arrow.clockwise") }.tint(Theme.accent)
                        }
                    }
                }
                if deliveries.isEmpty { Text("Nog geen afleveringen").font(.footnote).foregroundStyle(Theme.textSecondary) }
            }
            .cardRows()
            Section {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Webhook verwijderen", systemImage: "trash") }
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(hook.str("name"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { enabled = hook.b("enabled") ?? true; events = Set(hook.strings("eventTypes")) }
        .task { await loadDeliveries() }
        .refreshable { await loadDeliveries() }
        .confirmationDialog("Webhook verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) { Task { await delete() } }
        }
        .actionFeedback($feedback)
    }

    private func loadDeliveries() async {
        guard let api = store.api else { return }
        do {
            let doc = try await api.jget("/v1/webhooks/\(hook.id)/deliveries", [("limit", "50"), ("include", "event")])
            deliveries = doc.data
            included = doc.included
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let api = store.api else { return }
        do {
            try await api.jpatch("/v1/webhooks/\(hook.id)", type: "webhooks", id: hook.id, attributes: ["enabled": enabled, "eventTypes": Array(events)])
            feedback = L("Opgeslagen")
            await onChange()
        } catch { self.error = error.localizedDescription }
    }

    private func ping() async {
        guard let api = store.api else { return }
        do {
            try await api.jcreate("/v1/webhookPings", type: "webhookPings", relationships: ["webhook": ("webhooks", hook.id)])
            feedback = L("Testbericht verstuurd")
            try? await Task.sleep(for: .seconds(2))
            await loadDeliveries()
        } catch { self.error = error.localizedDescription }
    }

    private func redeliver(_ d: JRes) async {
        guard let api = store.api else { return }
        do {
            try await api.jcreate("/v1/webhookDeliveries", type: "webhookDeliveries", relationships: ["template": ("webhookDeliveries", d.id)])
            feedback = L("Opnieuw verstuurd")
            await loadDeliveries()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        guard let api = store.api else { return }
        do { try await api.jdelete("/v1/webhooks/\(hook.id)"); await onChange(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

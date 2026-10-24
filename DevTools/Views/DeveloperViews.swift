import SwiftUI

// MARK: - Shared building blocks for the new App Store Connect screens

/// Loads a JDoc and keeps loading/error state. Used by most of the new screens.
@MainActor
@Observable
final class Loader {
    var doc = JDoc()
    var loading = false
    var error: String?
    var loaded = false

    func run(_ op: @escaping () async throws -> JDoc) async {
        loading = true
        defer { loading = false; loaded = true }
        do { doc = try await op(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

/// Icon + title + subtitle row used across the new lists.
struct InfoRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = Theme.accent
    var badge: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(3)
                }
            }
            Spacer(minLength: 6)
            if let trailing { Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary) }
            if let badge { StateBadge(state: badge) }
        }
    }
}

/// Empty / loading / error overlay for lists.
struct ListStatus: View {
    let loader: Loader
    var empty: String = "Niets gevonden"

    var body: some View {
        if loader.loading && loader.doc.data.isEmpty {
            ProgressView()
        } else if loader.loaded && loader.doc.data.isEmpty && loader.error == nil {
            ContentUnavailableView(LS(empty), systemImage: "tray")
        }
    }
}

/// Navigation row with a coloured icon (same style as the app detail "manage" card).
struct ManageRow<D: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let destination: () -> D

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(LS(title)).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Team & developer resources (users, invitations, certificates, identifiers, devices, profiles)

struct DeveloperResourcesView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { UsersView() } label: { InfoRow(title: L("Gebruikers en toegang"), subtitle: L("Teamleden, rollen en uitnodigingen"), icon: "person.2.fill", tint: Theme.accent) }
            } header: { Text("Team") }
            .cardRows()
            Section {
                NavigationLink { CertificatesView() } label: { InfoRow(title: L("Certificaten"), subtitle: L("Ontwikkel- en distributiecertificaten"), icon: "checkmark.seal.fill", tint: Theme.live) }
                NavigationLink { BundleIDsView() } label: { InfoRow(title: L("Identifiers"), subtitle: L("Bundle ID's van je apps"), icon: "tag.fill", tint: Theme.pending) }
                NavigationLink { DevicesView() } label: { InfoRow(title: L("Toestellen"), subtitle: L("Geregistreerde testtoestellen"), icon: "iphone", tint: Theme.cyan) }
                NavigationLink { ProfilesView() } label: { InfoRow(title: L("Profielen"), subtitle: L("Provisioning profiles"), icon: "doc.badge.gearshape.fill", tint: Theme.review) }
            } header: { Text("Certificaten, identifiers en profielen") }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Team & ontwikkeling")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum TeamRoles {
    static let all = ["ADMIN", "APP_MANAGER", "DEVELOPER", "MARKETING", "SALES", "FINANCE", "CUSTOMER_SUPPORT", "ACCESS_TO_REPORTS", "CREATE_APPS", "GENERATE_INDIVIDUAL_KEYS"]
    static func label(_ r: String) -> String {
        switch r {
        case "ACCOUNT_HOLDER": return L("Accounthouder")
        case "ADMIN": return L("Beheerder")
        case "APP_MANAGER": return L("App-beheerder")
        case "DEVELOPER": return L("Ontwikkelaar")
        case "MARKETING": return L("Marketing")
        case "SALES": return L("Verkoop")
        case "FINANCE": return L("Financiën")
        case "CUSTOMER_SUPPORT": return L("Klantenservice")
        case "ACCESS_TO_REPORTS": return L("Toegang tot rapporten")
        case "CREATE_APPS": return L("Apps aanmaken")
        case "GENERATE_INDIVIDUAL_KEYS": return L("Eigen API-sleutels")
        default: return Pretty.label(r)
        }
    }
}

struct UsersView: View {
    @Environment(DevStore.self) private var store
    @State private var users = Loader()
    @State private var invites = Loader()
    @State private var showInvite = false
    @State private var editing: JRes?
    @State private var feedback: String?
    @State private var error: String?

    var body: some View {
        List {
            if let e = error ?? users.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            Section {
                ForEach(users.doc.data) { u in
                    Button { editing = u } label: {
                        InfoRow(title: "\(u.str("firstName")) \(u.str("lastName"))".trimmingCharacters(in: .whitespaces),
                                subtitle: u.str("username") + " · " + u.strings("roles").map(TeamRoles.label).joined(separator: ", "),
                                icon: "person.fill", tint: Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if !u.strings("roles").contains("ACCOUNT_HOLDER") {
                            Button(role: .destructive) { Task { await removeUser(u) } } label: { Label("Verwijder", systemImage: "trash") }
                        }
                    }
                }
            } header: { Text("Gebruikers (\(users.doc.data.count))") }
            .cardRows()
            Section {
                ForEach(invites.doc.data) { i in
                    InfoRow(title: i.str("email"),
                            subtitle: i.strings("roles").map(TeamRoles.label).joined(separator: ", ") + (i.date("expirationDate").map { " · " + L("verloopt \(Fmt.day($0))") } ?? ""),
                            icon: "envelope.fill", tint: Theme.pending)
                        .swipeActions {
                            Button(role: .destructive) { Task { await cancelInvite(i) } } label: { Label("Intrekken", systemImage: "xmark") }
                        }
                }
                Button { showInvite = true } label: { Label("Iemand uitnodigen", systemImage: "person.badge.plus") }
            } header: { Text("Uitnodigingen") }
            .cardRows()
        }
        .themedList()
        .overlay { if users.loading && users.doc.data.isEmpty { ProgressView() } }
        .navigationTitle("Gebruikers en toegang")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showInvite) { InviteUserSheet { await load() } }
        .sheet(item: $editing) { u in EditRolesSheet(user: u) { await load() } }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        await users.run { try await api.jget("/v1/users", [("limit", "200")], all: true) }
        await invites.run { try await api.jget("/v1/userInvitations", [("limit", "200")], all: true) }
    }

    private func removeUser(_ u: JRes) async {
        guard let api = store.api else { return }
        do { try await api.jdelete("/v1/users/\(u.id)"); feedback = L("Gebruiker verwijderd"); await load() }
        catch { self.error = error.localizedDescription }
    }

    private func cancelInvite(_ i: JRes) async {
        guard let api = store.api else { return }
        do { try await api.jdelete("/v1/userInvitations/\(i.id)"); feedback = L("Uitnodiging ingetrokken"); await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct RolePicker: View {
    @Binding var roles: Set<String>
    var body: some View {
        ForEach(TeamRoles.all, id: \.self) { r in
            Toggle(TeamRoles.label(r), isOn: Binding(get: { roles.contains(r) }, set: { on in if on { roles.insert(r) } else { roles.remove(r) } }))
        }
    }
}

struct InviteUserSheet: View {
    var onDone: () async -> Void
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var first = ""
    @State private var last = ""
    @State private var roles: Set<String> = ["DEVELOPER"]
    @State private var allApps = true
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(Theme.rejected).font(.footnote) }
                Section {
                    TextField("E-mail", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Voornaam", text: $first)
                    TextField("Achternaam", text: $last)
                }
                Section("Rollen") { RolePicker(roles: $roles) }
                Section { Toggle("Toegang tot alle apps", isOn: $allApps) }
            }
            .navigationTitle("Uitnodigen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verstuur") { Task { await send() } }.disabled(working || email.isEmpty || first.isEmpty || last.isEmpty || roles.isEmpty)
                }
            }
        }
    }

    private func send() async {
        guard let api = store.api else { return }
        working = true
        defer { working = false }
        do {
            try await api.jcreate("/v1/userInvitations", type: "userInvitations", attributes: [
                "email": email, "firstName": first, "lastName": last, "roles": Array(roles), "allAppsVisible": allApps, "provisioningAllowed": roles.contains("DEVELOPER")
            ])
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct EditRolesSheet: View {
    let user: JRes
    var onDone: () async -> Void
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var roles: Set<String> = []
    @State private var allApps = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(Theme.rejected).font(.footnote) }
                Section { LabeledContent("Gebruikersnaam", value: user.str("username")) }
                if user.strings("roles").contains("ACCOUNT_HOLDER") {
                    Text("De rollen van de accounthouder kun je niet wijzigen.").font(.footnote).foregroundStyle(Theme.textSecondary)
                } else {
                    Section("Rollen") { RolePicker(roles: $roles) }
                    Section { Toggle("Toegang tot alle apps", isOn: $allApps) }
                }
            }
            .navigationTitle("\(user.str("firstName")) \(user.str("lastName"))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } }
                if !user.strings("roles").contains("ACCOUNT_HOLDER") {
                    ToolbarItem(placement: .confirmationAction) { Button("Bewaar") { Task { await save() } }.disabled(roles.isEmpty) }
                }
            }
            .onAppear { roles = Set(user.strings("roles")); allApps = user.b("allAppsVisible") ?? true }
        }
    }

    private func save() async {
        guard let api = store.api else { return }
        do {
            try await api.jpatch("/v1/users/\(user.id)", type: "users", id: user.id, attributes: ["roles": Array(roles), "allAppsVisible": allApps])
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct CertificatesView: View {
    @Environment(DevStore.self) private var store
    @State private var loader = Loader()
    @State private var revoke: JRes?
    @State private var feedback: String?

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            ForEach(loader.doc.data.sorted { ($0.date("expirationDate") ?? .distantPast) > ($1.date("expirationDate") ?? .distantPast) }) { c in
                let exp = c.date("expirationDate")
                let expired = (exp ?? .distantFuture) < .now
                InfoRow(title: c.s("displayName") ?? c.str("name"),
                        subtitle: Pretty.label(c.s("certificateType")) + " · " + (expired ? L("verlopen") : L("geldig tot \(Fmt.day(exp))")),
                        icon: "checkmark.seal.fill", tint: expired ? Theme.textSecondary : Theme.live)
                    .swipeActions { Button(role: .destructive) { revoke = c } label: { Label("Intrekken", systemImage: "xmark.seal") } }
            }
            .cardRows()
        }
        .themedList()
        .overlay { ListStatus(loader: loader, empty: "Geen certificaten") }
        .navigationTitle("Certificaten")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Certificaat intrekken?", isPresented: Binding(get: { revoke != nil }, set: { if !$0 { revoke = nil } }), titleVisibility: .visible) {
            Button("Intrekken", role: .destructive) { if let c = revoke { Task { await doRevoke(c) } } }
        } message: { Text("Apps die met dit certificaat zijn ondertekend kunnen niet meer worden geïnstalleerd voor ontwikkeling. Dit kan niet ongedaan gemaakt worden.") }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/certificates", [("limit", "200")], all: true) }
    }

    private func doRevoke(_ c: JRes) async {
        guard let api = store.api else { return }
        do { try await api.jdelete("/v1/certificates/\(c.id)"); feedback = L("Certificaat ingetrokken"); await load() }
        catch { loader.error = error.localizedDescription }
    }
}

struct BundleIDsView: View {
    @Environment(DevStore.self) private var store
    @State private var loader = Loader()
    @State private var showNew = false
    @State private var name = ""
    @State private var identifier = ""
    @State private var platform = "IOS"
    @State private var feedback: String?

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            ForEach(loader.doc.data.sorted { $0.str("identifier") < $1.str("identifier") }) { b in
                InfoRow(title: b.str("name"), subtitle: b.str("identifier") + " · " + Platform.label(b.str("platform")), icon: "tag.fill", tint: Theme.pending)
                    .contextMenu { Button { UIPasteboard.general.string = b.str("identifier"); feedback = L("Gekopieerd") } label: { Label("Kopieer", systemImage: "doc.on.doc") } }
            }
            .cardRows()
        }
        .themedList()
        .overlay { ListStatus(loader: loader, empty: "Geen identifiers") }
        .navigationTitle("Identifiers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") } } }
        .task { await load() }
        .refreshable { await load() }
        .alert("Nieuwe identifier", isPresented: $showNew) {
            TextField("Naam", text: $name)
            TextField("Bundle ID (bijv. com.bedrijf.app)", text: $identifier).textInputAutocapitalization(.never)
            Button("Annuleer", role: .cancel) {}
            Button("Maak aan") { Task { await create() } }
        } message: { Text("Wordt aangemaakt voor iOS. Andere platforms kun je in App Store Connect toevoegen.") }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/bundleIds", [("limit", "200"), ("fields[bundleIds]", "name,identifier,platform,seedId")], all: true) }
    }

    private func create() async {
        guard let api = store.api, !identifier.isEmpty else { return }
        do {
            try await api.jcreate("/v1/bundleIds", type: "bundleIds", attributes: ["name": name.isEmpty ? identifier : name, "identifier": identifier, "platform": platform])
            feedback = L("Identifier aangemaakt"); name = ""; identifier = ""
            await load()
        } catch { loader.error = error.localizedDescription }
    }
}

struct DevicesView: View {
    @Environment(DevStore.self) private var store
    @State private var loader = Loader()
    @State private var showNew = false
    @State private var name = ""
    @State private var udid = ""
    @State private var feedback: String?

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            ForEach(loader.doc.data.sorted { $0.str("name").localizedCaseInsensitiveCompare($1.str("name")) == .orderedAscending }) { d in
                let enabled = d.s("status") == "ENABLED"
                InfoRow(title: d.str("name"),
                        subtitle: [d.s("model"), Pretty.label(d.s("deviceClass")), d.s("udid")].compactMap { $0 }.joined(separator: " · "),
                        icon: icon(d.s("deviceClass")), tint: enabled ? Theme.cyan : Theme.textSecondary)
                    .swipeActions {
                        Button { Task { await setStatus(d, enabled ? "DISABLED" : "ENABLED") } } label: {
                            Label(enabled ? "Uitschakelen" : "Inschakelen", systemImage: enabled ? "pause.circle" : "play.circle")
                        }.tint(enabled ? .orange : .green)
                    }
            }
            .cardRows()
        }
        .themedList()
        .overlay { ListStatus(loader: loader, empty: "Geen toestellen") }
        .navigationTitle("Toestellen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") } } }
        .task { await load() }
        .refreshable { await load() }
        .alert("Toestel registreren", isPresented: $showNew) {
            TextField("Naam", text: $name)
            TextField("UDID", text: $udid).textInputAutocapitalization(.never)
            Button("Annuleer", role: .cancel) {}
            Button("Registreer") { Task { await register() } }
        } message: { Text("De UDID vind je in Finder of Xcode als het toestel is aangesloten.") }
        .actionFeedback($feedback)
    }

    private func icon(_ cls: String?) -> String {
        switch cls {
        case "IPAD": return "ipad"
        case "APPLE_WATCH": return "applewatch"
        case "APPLE_TV": return "appletv"
        case "MAC": return "laptopcomputer"
        case "APPLE_VISION_PRO": return "visionpro"
        default: return "iphone"
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/devices", [("limit", "200")], all: true) }
    }

    private func register() async {
        guard let api = store.api, !udid.isEmpty else { return }
        do {
            try await api.jcreate("/v1/devices", type: "devices", attributes: ["name": name.isEmpty ? udid : name, "udid": udid.trimmingCharacters(in: .whitespaces), "platform": "IOS"])
            feedback = L("Toestel geregistreerd"); name = ""; udid = ""
            await load()
        } catch { loader.error = error.localizedDescription }
    }

    private func setStatus(_ d: JRes, _ status: String) async {
        guard let api = store.api else { return }
        do { try await api.jpatch("/v1/devices/\(d.id)", type: "devices", id: d.id, attributes: ["status": status]); await load() }
        catch { loader.error = error.localizedDescription }
    }
}

struct ProfilesView: View {
    @Environment(DevStore.self) private var store
    @State private var loader = Loader()
    @State private var feedback: String?

    var body: some View {
        List {
            if let e = loader.error { ErrorBanner(message: e).listRowBackground(Color.clear) }
            ForEach(loader.doc.data.sorted { $0.str("name") < $1.str("name") }) { p in
                let active = p.s("profileState") == "ACTIVE"
                InfoRow(title: p.str("name"),
                        subtitle: Pretty.label(p.s("profileType")) + " · " + L("verloopt \(Fmt.day(p.date("expirationDate")))"),
                        icon: "doc.badge.gearshape.fill", tint: active ? Theme.review : Theme.textSecondary)
                    .swipeActions { Button(role: .destructive) { Task { await delete(p) } } label: { Label("Verwijder", systemImage: "trash") } }
            }
            .cardRows()
        }
        .themedList()
        .overlay { ListStatus(loader: loader, empty: "Geen profielen") }
        .navigationTitle("Profielen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        await loader.run { try await api.jget("/v1/profiles", [("limit", "200"), ("fields[profiles]", "name,platform,profileType,profileState,uuid,createdDate,expirationDate")], all: true) }
    }

    private func delete(_ p: JRes) async {
        guard let api = store.api else { return }
        do { try await api.jdelete("/v1/profiles/\(p.id)"); feedback = L("Profiel verwijderd"); await load() }
        catch { loader.error = error.localizedDescription }
    }
}

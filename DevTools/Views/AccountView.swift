import SwiftUI
import UniformTypeIdentifiers

struct AccountView: View {
    @Environment(DevStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearance: AppearanceSetting = .system
    @State private var showAdd = false
    @State private var editing: DeveloperAccount?
    @State private var feedback: String?

    var body: some View {
        List {
            if store.isDemo {
                Section {
                    Label("Demo-modus actief – voorbeeldgegevens", systemImage: "play.rectangle.fill").foregroundStyle(Theme.accent)
                    Text("Dit is de demo-modus. Koppel je eigen App Store Connect-account om echte gegevens te zien.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    Button(role: .destructive) { store.endDemo() } label: { Label("Demo afsluiten", systemImage: "xmark.circle") }
                } header: { Text("Demo-modus") }
                .cardRows()
            }
            Section {
                ForEach(store.accounts) { item in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.brandGradient)
                            Text(String(item.name.prefix(1)).uppercased()).font(.headline).foregroundStyle(.white)
                        }
                        .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body.weight(.medium))
                            Text("Key \(item.keyID)\(item.hasVendor ? " · vendor \(item.vendorNumber ?? "")" : "")")
                                .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        if item.id == store.selectedID { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(item) }
                    .swipeActions {
                        Button(role: .destructive) { store.remove(item) } label: { Label("Verwijder", systemImage: "trash") }
                        Button { editing = item } label: { Label("Wijzig", systemImage: "pencil") }.tint(Theme.accent)
                    }
                    .contextMenu {
                        Button { editing = item } label: { Label("Wijzigen", systemImage: "pencil") }
                        Button(role: .destructive) { store.remove(item) } label: { Label("Verwijderen", systemImage: "trash") }
                    }
                }
                Button { showAdd = true } label: { Label("App Store Connect-account toevoegen", systemImage: "plus.circle.fill") }
            } header: { Text("Accounts") } footer: {
                Text("Veeg naar links om te wijzigen (vendornummer) of te verwijderen. Tik om te wisselen.")
            }
            .cardRows()

            if let active = store.active, !active.hasVendor {
                Section {
                    Button { editing = active } label: { Label("Vendornummer invullen voor downloads", systemImage: "chart.bar.xaxis") }
                }
                .cardRows()
            }

            Section {
                Picker(selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { Label(LS($0.label), systemImage: $0.icon).tag($0) }
                } label: { Label("Thema", systemImage: "paintbrush") }
                Picker(selection: Binding(
                    get: { LanguageManager.selected },
                    set: { newValue in
                        LanguageManager.set(newValue)
                        store.publishSnapshot()
                    }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text("\(lang.flag)  \(lang.nativeName)").tag(lang)
                    }
                } label: { Label("Taal", systemImage: "globe") }
                .pickerStyle(.navigationLink)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Label("Taal wijzigen in iOS-instellingen", systemImage: "gear") }
            } header: { Text("Weergave") } footer: {
                Text("Automatisch volgt de taal van je toestel (anders Engels). Widgets en Apple Watch gebruiken dezelfde taal.")
            }
            .cardRows()

            Section("Gegevens") {
                Button {
                    SalesEngine.clearCache()
                    Task { await store.refreshSales(force: true) }
                    feedback = "Rapportcache gewist"
                } label: { Label("Downloadrapporten opnieuw ophalen", systemImage: "arrow.clockwise.circle") }
                if let last = store.lastRefresh { LabeledContent("Laatst ververst", value: Fmt.date(last)) }
            }
            .cardRows()

            Section("Hulp") {
                NavigationLink { GuideView() } label: {
                    Label("Handleiding: API-sleutel, Issuer ID & vendornummer", systemImage: "book.pages.fill")
                }
                Button { openURL(URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!) } label: {
                    Label("API-sleutels beheren", systemImage: "key")
                }
                Button { openURL(URL(string: "https://appstoreconnect.apple.com/business")!) } label: {
                    Label("Vendornummer opzoeken", systemImage: "number.circle")
                }
                Button { openURL(URL(string: "https://developer.apple.com/documentation/appstoreconnectapi")!) } label: {
                    Label("App Store Connect API-documentatie", systemImage: "book")
                }
            }
            .cardRows()

            Section {
                LabeledContent("Versie", value: appVersion)
                Text("Onafhankelijke app, niet gelieerd aan Apple. Je .p8-sleutel blijft in de Keychain van dit toestel.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Text("© DevTools - PixelForges").font(.caption).foregroundStyle(Theme.textSecondary)
            } header: { Text("Over") }
            .cardRows()
        }
        .themedList()
        .navigationTitle("Account")
        .sheet(isPresented: $showAdd) { AccountEditorSheet(existing: nil) }
        .sheet(item: $editing) { AccountEditorSheet(existing: $0) }
        .actionFeedback($feedback)
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

/// Add a new App Store Connect API account or edit an existing one.
struct AccountEditorSheet: View {
    let existing: DeveloperAccount?
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var issuer = ""
    @State private var keyID = ""
    @State private var vendor = ""
    @State private var pem = ""
    @State private var showPicker = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam (bijv. PixelForges)", text: $name)
                    if existing == nil {
                        TextField("Issuer ID", text: $issuer).textInputAutocapitalization(.never).autocorrectionDisabled().font(.callout.monospaced())
                        TextField("Key ID", text: $keyID).textInputAutocapitalization(.never).autocorrectionDisabled().font(.callout.monospaced())
                        Button { showPicker = true } label: {
                            Label(LS(pem.isEmpty ? "Kies AuthKey_*.p8" : "Sleutel geïmporteerd ✓"), systemImage: pem.isEmpty ? "doc.badge.plus" : "checkmark.seal.fill")
                        }
                        .tint(pem.isEmpty ? Theme.accent : Theme.live)
                    } else {
                        LabeledContent("Issuer ID", value: existing?.issuerID ?? "")
                        LabeledContent("Key ID", value: existing?.keyID ?? "")
                    }
                } header: { Text("App Store Connect API") } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Maak een teamsleutel aan in App Store Connect → Gebruikers en toegang → Integraties → App Store Connect API. Kies de rol Admin voor alle functies.")
                        NavigationLink { GuideView() } label: { Label("Hoe kom ik hieraan? Bekijk de handleiding", systemImage: "book.pages") }
                            .font(.footnote.weight(.semibold))
                    }
                }
                Section {
                    TextField("Vendornummer (bijv. 8xxxxxxx)", text: $vendor).keyboardType(.numberPad)
                } header: { Text("Downloads & opbrengst") } footer: {
                    Text("Te vinden in App Store Connect → Business, naast je adres. Nodig voor Sales Reports.")
                }
                if let error { Section { Text(error).foregroundStyle(Theme.rejected) } }
            }
            .navigationTitle(LS(existing == nil ? "Account koppelen" : "Account wijzigen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { save() }
                        .fontWeight(.semibold)
                        .disabled(existing == nil && (issuer.isEmpty || keyID.isEmpty || pem.isEmpty))
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.data, .plainText, .item], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    pem = try String(contentsOf: url, encoding: .utf8)
                    let file = url.deletingPathExtension().lastPathComponent
                    if keyID.isEmpty, file.hasPrefix("AuthKey_") { keyID = String(file.dropFirst("AuthKey_".count)) }
                    if !pem.contains("PRIVATE KEY") { error = "Dit lijkt geen geldige .p8-sleutel" } else { error = nil }
                } catch { self.error = error.localizedDescription }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    vendor = existing.vendorNumber ?? ""
                }
            }
        }
    }

    private func save() {
        if var account = existing {
            account.name = name.isEmpty ? account.name : name
            account.vendorNumber = vendor.trimmingCharacters(in: .whitespaces)
            store.update(account)
            dismiss()
            return
        }
        do {
            try store.add(name: name.isEmpty ? "App Store Connect" : name, issuer: issuer, key: keyID, pem: pem, vendor: vendor)
            dismiss()
            Task { await store.refresh() }
        } catch { self.error = error.localizedDescription }
    }
}

import SwiftUI

// MARK: - In-app purchases, subscriptions and offer codes

enum ProductKind {
    case iap, subscription

    func path(_ id: String) -> String { self == .iap ? "/v2/inAppPurchases/\(id)" : "/v1/subscriptions/\(id)" }
    var type: String { self == .iap ? "inAppPurchases" : "subscriptions" }
    func localizations(_ id: String) -> String { self == .iap ? "/v2/inAppPurchases/\(id)/inAppPurchaseLocalizations" : "/v1/subscriptions/\(id)/subscriptionLocalizations" }
    var localizationType: String { self == .iap ? "inAppPurchaseLocalizations" : "subscriptionLocalizations" }
    func offerCodes(_ id: String) -> String { self == .iap ? "/v2/inAppPurchases/\(id)/offerCodes" : "/v1/subscriptions/\(id)/offerCodes" }
    var offerCodeType: String { self == .iap ? "inAppPurchaseOfferCodes" : "subscriptionOfferCodes" }
    var oneTimeType: String { self == .iap ? "inAppPurchaseOfferCodeOneTimeUseCodes" : "subscriptionOfferCodeOneTimeUseCodes" }
    var submissionPath: String { self == .iap ? "/v1/inAppPurchaseSubmissions" : "/v1/subscriptionSubmissions" }
    var submissionType: String { self == .iap ? "inAppPurchaseSubmissions" : "subscriptionSubmissions" }
    var submissionRel: (String, String) { self == .iap ? ("inAppPurchaseV2", "inAppPurchases") : ("subscription", "subscriptions") }
}

struct IAPView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var tab = 0
    @State private var iaps: [JRes] = []
    @State private var groups: [JRes] = []
    @State private var subs: [JRes] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showNew = false

    var body: some View {
        List {
            Section {
                Picker("Soort", selection: $tab) {
                    Text("In-app aankopen").tag(0)
                    Text("Abonnementen").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if tab == 0 {
                Section {
                    ForEach(iaps.sorted { $0.str("name") < $1.str("name") }) { p in
                        NavigationLink { ProductDetailView(kind: .iap, product: p) } label: {
                            InfoRow(title: p.str("name"), subtitle: p.str("productId") + " · " + typeLabel(p.s("inAppPurchaseType")),
                                    icon: "cart.fill", tint: Theme.review, badge: p.s("state"))
                        }
                    }
                    if iaps.isEmpty && !loading { Text("Nog geen in-app aankopen").font(.footnote).foregroundStyle(Theme.textSecondary) }
                    Button { showNew = true } label: { Label("Nieuwe in-app aankoop", systemImage: "plus.circle") }
                }
                .cardRows()
            } else {
                ForEach(groups) { g in
                    Section(g.str("referenceName")) {
                        ForEach(subs.filter { g.relIDs("subscriptions").contains($0.id) }.sorted { ($0.i("groupLevel") ?? 0) < ($1.i("groupLevel") ?? 0) }) { s in
                            NavigationLink { ProductDetailView(kind: .subscription, product: s) } label: {
                                InfoRow(title: s.str("name"), subtitle: s.str("productId") + " · " + periodLabel(s.s("subscriptionPeriod")),
                                        icon: "arrow.triangle.2.circlepath.circle.fill", tint: Theme.live, badge: s.s("state"))
                            }
                        }
                    }
                    .cardRows()
                }
                if groups.isEmpty && !loading {
                    Section { Text("Nog geen abonnementen").font(.footnote).foregroundStyle(Theme.textSecondary) }.cardRows()
                }
            }
            Section {
                Text("Promotiecodes voor in-app aankopen zijn sinds 26 maart 2026 vervangen door aanbiedingscodes; die beheer je per product hierboven. Promotiecodes voor de app zelf kun je alleen in App Store Connect aanmaken.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                if let url = URL(string: "https://appstoreconnect.apple.com/apps/\(app.id)/distribution/promocodes") {
                    Button { openURL(url) } label: { Label("Promotiecodes in App Store Connect", systemImage: "safari") }
                }
            } header: { Text("Promotiecodes") }
            .cardRows()
        }
        .themedList()
        .overlay { if loading && iaps.isEmpty && groups.isEmpty { ProgressView() } }
        .navigationTitle("In-app aankopen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNew) { NewIAPSheet(appID: app.id) { await load() } }
    }

    private func typeLabel(_ t: String?) -> String {
        switch t {
        case "CONSUMABLE": return L("Verbruiksartikel")
        case "NON_CONSUMABLE": return L("Niet-verbruiksartikel")
        case "NON_RENEWING_SUBSCRIPTION": return L("Niet-verlengend abonnement")
        default: return Pretty.label(t)
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do {
            async let i = api.jget("/v1/apps/\(app.id)/inAppPurchasesV2", [("limit", "200")], all: true)
            async let g = api.jget("/v1/apps/\(app.id)/subscriptionGroups", [("limit", "50"), ("include", "subscriptions")], all: true)
            iaps = try await i.data
            let gd = try await g
            groups = gd.data
            subs = gd.included.filter { $0.type == "subscriptions" }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

func periodLabel(_ p: String?) -> String {
    switch p {
    case "ONE_WEEK": return L("1 week")
    case "ONE_MONTH": return L("1 maand")
    case "TWO_MONTHS": return L("2 maanden")
    case "THREE_MONTHS": return L("3 maanden")
    case "SIX_MONTHS": return L("6 maanden")
    case "ONE_YEAR": return L("1 jaar")
    default: return Pretty.label(p)
    }
}

struct NewIAPSheet: View {
    let appID: String
    var onDone: () async -> Void
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var productId = ""
    @State private var type = "NON_CONSUMABLE"
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(Theme.rejected).font(.footnote) }
                TextField("Naam (alleen voor jezelf)", text: $name)
                TextField("Product-ID (bijv. com.bedrijf.app.pro)", text: $productId).textInputAutocapitalization(.never)
                Picker("Soort", selection: $type) {
                    Text("Verbruiksartikel").tag("CONSUMABLE")
                    Text("Niet-verbruiksartikel").tag("NON_CONSUMABLE")
                    Text("Niet-verlengend abonnement").tag("NON_RENEWING_SUBSCRIPTION")
                }
                Text("Prijs, beschikbaarheid en screenshot voor de review stel je daarna in App Store Connect in.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .navigationTitle("Nieuwe in-app aankoop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Maak aan") { Task { await create() } }.disabled(name.isEmpty || productId.isEmpty || working) }
            }
        }
    }

    private func create() async {
        guard let api = store.api else { return }
        working = true
        defer { working = false }
        do {
            try await api.jcreate("/v2/inAppPurchases", type: "inAppPurchases", attributes: ["name": name, "productId": productId, "inAppPurchaseType": type],
                                  relationships: ["app": ("apps", appID)])
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ProductDetailView: View {
    let kind: ProductKind
    let product: JRes
    @Environment(DevStore.self) private var store
    @State private var current: JRes?
    @State private var locs: [JRes] = []
    @State private var edits: [String: (name: String, description: String)] = [:]
    @State private var offers: [JRes] = []
    @State private var reviewNote = ""
    @State private var familySharable = false
    @State private var error: String?
    @State private var feedback: String?
    @State private var working = false

    var body: some View {
        let p = current ?? product
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            Section {
                HStack { Text(p.str("name")).font(.title3.weight(.bold)); Spacer(); StateBadge(state: p.str("state")) }
                LabeledContent("Product-ID", value: p.str("productId"))
                if kind == .subscription { LabeledContent("Periode", value: periodLabel(p.s("subscriptionPeriod"))) }
                Toggle("Delen met gezin", isOn: $familySharable)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notitie voor de review").font(.caption).foregroundStyle(Theme.textSecondary)
                    TextField("Notitie voor de review", text: $reviewNote, axis: .vertical).lineLimit(2...6)
                }
                Button { Task { await saveProduct() } } label: { Label("Bewaar", systemImage: "checkmark.circle") }.disabled(working)
            }
            .cardRows()

            Section("Weergavenaam en beschrijving") {
                ForEach(locs) { l in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Locales.flag(l.str("locale"))) \(Locales.name(l.str("locale")))").font(.caption.weight(.semibold))
                        TextField("Weergavenaam", text: Binding(get: { edits[l.id]?.name ?? "" }, set: { edits[l.id] = ($0, edits[l.id]?.description ?? "") }))
                        TextField("Beschrijving", text: Binding(get: { edits[l.id]?.description ?? "" }, set: { edits[l.id] = (edits[l.id]?.name ?? "", $0) }), axis: .vertical)
                            .lineLimit(1...4).font(.footnote)
                        Button { Task { await saveLoc(l) } } label: { Label("Opslaan", systemImage: "checkmark.circle") }
                            .font(.footnote).disabled(working || (edits[l.id]?.name == l.str("name") && edits[l.id]?.description == l.str("description")))
                    }
                    .padding(.vertical, 2)
                }
                if locs.isEmpty { Text("Nog geen talen. Voeg ze toe in App Store Connect.").font(.footnote).foregroundStyle(Theme.textSecondary) }
            }
            .cardRows()

            Section {
                ForEach(offers) { o in
                    NavigationLink { OfferCodeView(kind: kind, offer: o) } label: {
                        InfoRow(title: o.str("name"),
                                subtitle: [o.s("offerMode").map(Pretty.label), o.s("duration").map(Pretty.label),
                                           o.i("totalNumberOfCodes").map { L("\($0) codes") }].compactMap { $0 }.joined(separator: " · "),
                                icon: "ticket.fill", tint: Theme.pending, badge: o.b("active") == false ? "INACTIVE" : nil)
                    }
                }
                if offers.isEmpty { Text("Nog geen aanbiedingscodes. Maak er een in App Store Connect; hier genereer je daarna codes.").font(.footnote).foregroundStyle(Theme.textSecondary) }
            } header: { Text("Aanbiedingscodes") }
            .cardRows()

            Section {
                Button { Task { await submit() } } label: { Label("Indienen voor review", systemImage: "paperplane") }
                    .disabled(working || p.s("state") != "READY_TO_SUBMIT")
            } footer: {
                Text("Kan alleen als de status 'Ready to submit' is. De eerste in-app aankoop dien je samen met een app-versie in.")
            }
            .cardRows()
        }
        .themedList()
        .navigationTitle(p.str("name"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        do {
            current = try await api.jget(kind.path(product.id)).data.first
            let c = current ?? product
            reviewNote = c.str("reviewNote")
            familySharable = c.b("familySharable") ?? false
            locs = (try? await api.jget(kind.localizations(product.id), [("limit", "50")]).data) ?? []
            for l in locs { edits[l.id] = (l.str("name"), l.str("description")) }
            offers = (try? await api.jget(kind.offerCodes(product.id), [("limit", "50")]).data) ?? []
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func perform(_ msg: String, _ op: () async throws -> Void) async {
        working = true
        defer { working = false }
        do { try await op(); feedback = msg; error = nil; await load() }
        catch { self.error = error.localizedDescription }
    }

    private func saveProduct() async {
        guard let api = store.api else { return }
        await perform(L("Opgeslagen")) {
            try await api.jpatch(kind.path(product.id), type: kind.type, id: product.id, attributes: ["reviewNote": reviewNote, "familySharable": familySharable])
        }
    }

    private func saveLoc(_ l: JRes) async {
        guard let api = store.api, let e = edits[l.id] else { return }
        let path = kind == .iap ? "/v1/inAppPurchaseLocalizations/\(l.id)" : "/v1/subscriptionLocalizations/\(l.id)"
        await perform(L("Opgeslagen")) {
            try await api.jpatch(path, type: kind.localizationType, id: l.id, attributes: ["name": e.name, "description": e.description])
        }
    }

    private func submit() async {
        guard let api = store.api else { return }
        await perform(L("Ingediend voor review")) {
            try await api.jcreate(kind.submissionPath, type: kind.submissionType, relationships: [kind.submissionRel.0: (kind.submissionRel.1, product.id)])
        }
    }
}

struct OfferCodeView: View {
    let kind: ProductKind
    let offer: JRes
    @Environment(DevStore.self) private var store
    @State private var batches: [JRes] = []
    @State private var custom: [JRes] = []
    @State private var count = 100
    @State private var expires = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var csv: String?
    @State private var working = false
    @State private var error: String?
    @State private var feedback: String?

    private var base: String { kind == .iap ? "/v1/inAppPurchaseOfferCodes/\(offer.id)" : "/v1/subscriptionOfferCodes/\(offer.id)" }

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            Section {
                LabeledContent("Naam", value: offer.str("name"))
                if let m = offer.s("offerMode") { LabeledContent("Soort", value: Pretty.label(m)) }
                if let d = offer.s("duration") { LabeledContent("Duur", value: Pretty.label(d)) }
                if !offer.strings("customerEligibilities").isEmpty {
                    LabeledContent("Voor", value: offer.strings("customerEligibilities").map(Pretty.label).joined(separator: ", "))
                }
            }
            .cardRows()
            Section {
                Stepper(value: $count, in: 1...10_000, step: count < 100 ? 10 : 100) { LabeledContent("Aantal codes", value: Fmt.number(count)) }
                DatePicker("Verloopt", selection: $expires, in: Date.now..., displayedComponents: .date)
                Button { Task { await generate() } } label: { Label("Codes genereren", systemImage: "wand.and.stars") }.disabled(working)
            } header: { Text("Eenmalige codes") } footer: {
                Text("Apple maakt de codes in de achtergrond; het kan even duren voordat je ze kunt downloaden.")
            }
            .cardRows()
            Section("Gegenereerde reeksen") {
                ForEach(batches.sorted { ($0.date("createdDate") ?? .distantPast) > ($1.date("createdDate") ?? .distantPast) }) { b in
                    Button { Task { await download(b) } } label: {
                        InfoRow(title: L("\(b.i("numberOfCodes") ?? 0) codes"),
                                subtitle: L("aangemaakt \(Fmt.day(b.date("createdDate"))) · verloopt \(Fmt.day(b.date("expirationDate")))"),
                                icon: "list.number", tint: b.b("active") == false ? Theme.textSecondary : Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                if batches.isEmpty { Text("Nog geen codes gegenereerd").font(.footnote).foregroundStyle(Theme.textSecondary) }
            }
            .cardRows()
            if !custom.isEmpty {
                Section("Eigen codes") {
                    ForEach(custom) { c in
                        LabeledContent(c.str("customCode"), value: L("\(c.i("numberOfCodes") ?? 0) keer"))
                    }
                }
                .cardRows()
            }
            if let csv {
                Section("Codes") {
                    ShareLink(item: csv) { Label("Deel codes (CSV)", systemImage: "square.and.arrow.up") }
                    Button { UIPasteboard.general.string = csv; feedback = L("Gekopieerd") } label: { Label("Kopieer alle codes", systemImage: "doc.on.doc") }
                    Text(csv.split(separator: "\n").prefix(20).joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled)
                }
                .cardRows()
            }
        }
        .themedList()
        .navigationTitle(offer.str("name"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .actionFeedback($feedback)
    }

    private func load() async {
        guard let api = store.api else { return }
        batches = (try? await api.jget("\(base)/oneTimeUseCodes", [("limit", "50")]).data) ?? []
        custom = (try? await api.jget("\(base)/customCodes", [("limit", "50")]).data) ?? []
    }

    private func generate() async {
        guard let api = store.api else { return }
        working = true
        defer { working = false }
        do {
            try await api.jcreate("/v1/\(kind.oneTimeType)", type: kind.oneTimeType,
                                  attributes: ["numberOfCodes": count, "expirationDate": AnalyticsEngine.dayFormatter.string(from: expires)],
                                  relationships: ["offerCode": (kind.offerCodeType, offer.id)])
            feedback = L("Codes worden aangemaakt")
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func download(_ batch: JRes) async {
        guard let api = store.api else { return }
        do {
            let data = try await api.raw("/v1/\(kind.oneTimeType)/\(batch.id)/values", accept: "text/csv")
            csv = String(decoding: data, as: UTF8.self)
        } catch { self.error = error.localizedDescription }
    }
}

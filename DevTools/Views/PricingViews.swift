import SwiftUI

/// ISO 3166 alpha-3 (App Store territories) → alpha-2 (flags and localized names).
enum Territory {
    static let map: [String: String] = {
        var m: [String: String] = [:]
        for pair in "ABW:AW,AFG:AF,AGO:AO,AIA:AI,ALA:AX,ALB:AL,AND:AD,ARE:AE,ARG:AR,ARM:AM,ASM:AS,ATA:AQ,ATF:TF,ATG:AG,AUS:AU,AUT:AT,AZE:AZ,BDI:BI,BEL:BE,BEN:BJ,BES:BQ,BFA:BF,BGD:BD,BGR:BG,BHR:BH,BHS:BS,BIH:BA,BLM:BL,BLR:BY,BLZ:BZ,BMU:BM,BOL:BO,BRA:BR,BRB:BB,BRN:BN,BTN:BT,BVT:BV,BWA:BW,CAF:CF,CAN:CA,CCK:CC,CHE:CH,CHL:CL,CHN:CN,CIV:CI,CMR:CM,COD:CD,COG:CG,COK:CK,COL:CO,COM:KM,CPV:CV,CRI:CR,CUB:CU,CUW:CW,CXR:CX,CYM:KY,CYP:CY,CZE:CZ,DEU:DE,DJI:DJ,DMA:DM,DNK:DK,DOM:DO,DZA:DZ,ECU:EC,EGY:EG,ERI:ER,ESH:EH,ESP:ES,EST:EE,ETH:ET,FIN:FI,FJI:FJ,FLK:FK,FRA:FR,FRO:FO,FSM:FM,GAB:GA,GBR:GB,GEO:GE,GGY:GG,GHA:GH,GIB:GI,GIN:GN,GLP:GP,GMB:GM,GNB:GW,GNQ:GQ,GRC:GR,GRD:GD,GRL:GL,GTM:GT,GUF:GF,GUM:GU,GUY:GY,HKG:HK,HMD:HM,HND:HN,HRV:HR,HTI:HT,HUN:HU,IDN:ID,IMN:IM,IND:IN,IOT:IO,IRL:IE,IRN:IR,IRQ:IQ,ISL:IS,ISR:IL,ITA:IT,JAM:JM,JEY:JE,JOR:JO,JPN:JP,KAZ:KZ,KEN:KE,KGZ:KG,KHM:KH,KIR:KI,KNA:KN,KOR:KR,KWT:KW,LAO:LA,LBN:LB,LBR:LR,LBY:LY,LCA:LC,LIE:LI,LKA:LK,LSO:LS,LTU:LT,LUX:LU,LVA:LV,MAC:MO,MAF:MF,MAR:MA,MCO:MC,MDA:MD,MDG:MG,MDV:MV,MEX:MX,MHL:MH,MKD:MK,MLI:ML,MLT:MT,MMR:MM,MNE:ME,MNG:MN,MNP:MP,MOZ:MZ,MRT:MR,MSR:MS,MTQ:MQ,MUS:MU,MWI:MW,MYS:MY,MYT:YT,NAM:NA,NCL:NC,NER:NE,NFK:NF,NGA:NG,NIC:NI,NIU:NU,NLD:NL,NOR:NO,NPL:NP,NRU:NR,NZL:NZ,OMN:OM,PAK:PK,PAN:PA,PCN:PN,PER:PE,PHL:PH,PLW:PW,PNG:PG,POL:PL,PRI:PR,PRK:KP,PRT:PT,PRY:PY,PSE:PS,PYF:PF,QAT:QA,REU:RE,ROU:RO,RUS:RU,RWA:RW,SAU:SA,SDN:SD,SEN:SN,SGP:SG,SGS:GS,SHN:SH,SJM:SJ,SLB:SB,SLE:SL,SLV:SV,SMR:SM,SOM:SO,SPM:PM,SRB:RS,SSD:SS,STP:ST,SUR:SR,SVK:SK,SVN:SI,SWE:SE,SWZ:SZ,SXM:SX,SYC:SC,SYR:SY,TCA:TC,TCD:TD,TGO:TG,THA:TH,TJK:TJ,TKL:TK,TKM:TM,TLS:TL,TON:TO,TTO:TT,TUN:TN,TUR:TR,TUV:TV,TWN:TW,TZA:TZ,UGA:UG,UKR:UA,UMI:UM,URY:UY,USA:US,UZB:UZ,VAT:VA,VCT:VC,VEN:VE,VGB:VG,VIR:VI,VNM:VN,VUT:VU,WLF:WF,WSM:WS,YEM:YE,ZAF:ZA,ZMB:ZM,ZWE:ZW".split(separator: ",") {
            let p = pair.split(separator: ":")
            if p.count == 2 { m[String(p[0])] = String(p[1]) }
        }
        return m
    }()
    static func iso2(_ id: String) -> String { map[id] ?? String(id.prefix(2)) }
    static func name(_ id: String) -> String { Fmt.countryName(iso2(id)) }
    static func flag(_ id: String) -> String { Fmt.flag(iso2(id)) }
}

// MARK: - Price and availability per country

struct PricingView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var scheduleID: String?
    @State private var base = "USA"
    @State private var baseCurrency = ""
    @State private var basePrice: JRes?
    @State private var prices: [(territory: String, currency: String, price: String, proceeds: String)] = []
    @State private var availabilityID: String?
    @State private var availableInNew = false
    @State private var territories: [JRes] = []
    @State private var territoryInfo: [String: JRes] = [:]
    @State private var loading = true
    @State private var error: String?
    @State private var feedback: String?
    @State private var showPrice = false
    @State private var query = ""
    @State private var tab = 0

    var body: some View {
        List {
            Section {
                Picker("Weergave", selection: $tab) {
                    Text("Prijs").tag(0)
                    Text("Beschikbaarheid").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if tab == 0 { priceSections } else { availabilitySections }
        }
        .themedList()
        .overlay { if loading && prices.isEmpty && territories.isEmpty { ProgressView() } }
        .searchable(text: $query, prompt: "Zoek land")
        .navigationTitle("Prijs en beschikbaarheid")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showPrice) { PricePickerSheet(appID: app.id, base: base) { await load(); feedback = L("Nieuwe prijs ingesteld") } }
        .actionFeedback($feedback)
    }

    @ViewBuilder private var priceSections: some View {
        Section {
            HStack {
                Text("\(Territory.flag(base)) \(Territory.name(base))").font(.subheadline)
                Spacer()
                Text(basePrice.map { priceText($0.str("customerPrice"), baseCurrency) } ?? "—").font(.title3.weight(.bold).monospacedDigit())
            }
            if let p = basePrice { LabeledContent("Jouw opbrengst", value: priceText(p.str("proceeds"), baseCurrency)) }
            Button { showPrice = true } label: { Label("Prijs wijzigen", systemImage: "tag") }
        } header: { Text("Basisprijs") } footer: {
            Text("Apple rekent de prijzen in andere landen automatisch om vanuit je basisland, tenzij je ze in App Store Connect handmatig vastzet.")
        }
        .cardRows()
        Section("Prijzen per land (\(prices.count))") {
            ForEach(prices.filter { query.isEmpty || Territory.name($0.territory).localizedCaseInsensitiveContains(query) }, id: \.territory) { p in
                HStack {
                    Text("\(Territory.flag(p.territory)) \(Territory.name(p.territory))").font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(priceText(p.price, p.currency)).font(.subheadline.monospacedDigit())
                        Text(L("opbrengst \(priceText(p.proceeds, p.currency))")).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .cardRows()
    }

    @ViewBuilder private var availabilitySections: some View {
        let available = territories.filter { $0.b("available") == true }.count
        Section {
            LabeledContent("Beschikbaar in", value: L("\(available) van \(territories.count) landen"))
            LabeledContent("Nieuwe landen automatisch", value: availableInNew ? L("Ja") : L("Nee"))
        }
        .cardRows()
        Section("Landen") {
            ForEach(territories.filter { t in query.isEmpty || Territory.name(t.rel("territory") ?? "").localizedCaseInsensitiveContains(query) }
                .sorted { Territory.name($0.rel("territory") ?? "") < Territory.name($1.rel("territory") ?? "") }) { t in
                let id = t.rel("territory") ?? ""
                Toggle(isOn: Binding(get: { t.b("available") == true }, set: { v in Task { await setAvailable(t, v) } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Territory.flag(id)) \(Territory.name(id))").font(.subheadline)
                        if let d = t.date("releaseDate") { Text(L("release \(Fmt.day(d))")).font(.caption2).foregroundStyle(Theme.textSecondary) }
                        if t.b("preOrderEnabled") == true { Text("Pre-order").font(.caption2).foregroundStyle(Theme.pending) }
                    }
                }
            }
        }
        .cardRows()
    }

    private func priceText(_ value: String, _ currency: String) -> String {
        guard let v = Double(value) else { return value.isEmpty ? "—" : value }
        if v == 0 { return L("Gratis") }
        return Fmt.money(v, currency)
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do {
            if let schedule = try await api.jget("/v1/apps/\(app.id)/appPriceSchedule").data.first {
                scheduleID = schedule.id
                let baseDoc = try? await api.jget("/v1/appPriceSchedules/\(schedule.id)/baseTerritory")
                if let b = baseDoc?.data.first { base = b.id; baseCurrency = b.str("currency") }
                let today = AnalyticsEngine.dayFormatter.string(from: .now)
                func current(_ list: [JRes]) -> [JRes] {
                    list.filter { p in
                        let start = p.s("startDate") ?? "", end = p.s("endDate") ?? ""
                        return (start.isEmpty || start <= today) && (end.isEmpty || end > today)
                    }
                }
                let manual = try await api.jget("/v1/appPriceSchedules/\(schedule.id)/manualPrices", [("include", "appPricePoint,territory"), ("limit", "200")], all: true)
                let auto = (try? await api.jget("/v1/appPriceSchedules/\(schedule.id)/automaticPrices", [("include", "appPricePoint,territory"), ("limit", "200")], all: true)) ?? JDoc()
                let incl = manual.included + auto.included
                var rows: [String: (territory: String, currency: String, price: String, proceeds: String)] = [:]
                for p in current(auto.data) + current(manual.data) {
                    guard let terr = p.rel("territory") else { continue }
                    let point = incl.first { $0.id == p.rel("appPricePoint") && $0.type == "appPricePoints" }
                    let currency = incl.first { $0.id == terr && $0.type == "territories" }?.str("currency") ?? ""
                    rows[terr] = (terr, currency, point?.str("customerPrice") ?? "", point?.str("proceeds") ?? "")
                    if terr == base, let point { basePrice = point; if baseCurrency.isEmpty { baseCurrency = currency } }
                }
                prices = rows.values.sorted { Territory.name($0.territory) < Territory.name($1.territory) }
            }
            if let availability = try? await api.jget("/v1/apps/\(app.id)/appAvailabilityV2").data.first {
                availabilityID = availability.id
                availableInNew = availability.b("availableInNewTerritories") ?? false
                territories = try await api.jget("/v2/appAvailabilities/\(availability.id)/territoryAvailabilities", [("limit", "200")], all: true).data
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func setAvailable(_ t: JRes, _ value: Bool) async {
        guard let api = store.api else { return }
        do {
            try await api.jpatch("/v1/territoryAvailabilities/\(t.id)", type: "territoryAvailabilities", id: t.id, attributes: ["available": value])
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct PricePickerSheet: View {
    let appID: String
    let base: String
    var onDone: () async -> Void
    @Environment(DevStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var points: [JRes] = []
    @State private var selected = ""
    @State private var currency = ""
    @State private var loading = true
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Theme.rejected).font(.footnote) }
                Section {
                    Text("Kies de nieuwe prijs in \(Territory.name(base)). De nieuwe prijs geldt meteen; andere landen worden automatisch omgerekend.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(points) { p in
                    Button { selected = p.id } label: {
                        HStack {
                            Text(label(p)).foregroundStyle(.primary)
                            Spacer()
                            Text(L("opbrengst \(Fmt.money(Double(p.str("proceeds")) ?? 0, currency))")).font(.caption).foregroundStyle(Theme.textSecondary)
                            if selected == p.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            }
            .overlay { if loading { ProgressView() } }
            .navigationTitle("Prijs wijzigen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Bewaar") { Task { await save() } }.disabled(selected.isEmpty || working) }
            }
            .task { await load() }
        }
    }

    private func label(_ p: JRes) -> String {
        let v = Double(p.str("customerPrice")) ?? 0
        return v == 0 ? L("Gratis") : Fmt.money(v, currency)
    }

    private func load() async {
        guard let api = store.api else { return }
        defer { loading = false }
        do {
            let doc = try await api.jget("/v1/apps/\(appID)/appPricePoints", [("filter[territory]", base), ("include", "territory"), ("limit", "200")], all: true, max: 1000)
            currency = doc.included.first { $0.type == "territories" }?.str("currency") ?? (base == "USA" ? "USD" : "")
            points = doc.data.sorted { (Double($0.str("customerPrice")) ?? 0) < (Double($1.str("customerPrice")) ?? 0) }
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let api = store.api else { return }
        working = true
        defer { working = false }
        let body: [String: Any] = [
            "data": ["type": "appPriceSchedules", "relationships": [
                "app": ["data": ["type": "apps", "id": appID]],
                "baseTerritory": ["data": ["type": "territories", "id": base]],
                "manualPrices": ["data": [["type": "appPrices", "id": "${price1}"]]],
            ]],
            "included": [["type": "appPrices", "id": "${price1}",
                          "attributes": ["startDate": NSNull(), "endDate": NSNull()],
                          "relationships": ["appPricePoint": ["data": ["type": "appPricePoints", "id": selected]]]]],
        ]
        do {
            try await api.jsend("POST", "/v1/appPriceSchedules", body)
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

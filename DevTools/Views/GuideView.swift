import SwiftUI

/// Step-by-step guide: how to get the API key (.p8), Issuer ID, Key ID and vendor number.
struct GuideView: View {
    @Environment(\.openURL) private var openURL
    @State private var expanded: Set<Int> = [1]

    struct Step: Identifiable {
        let id: Int
        let icon: String
        let tint: Color
        let title: String
        let summary: String
        let lines: [String]
        var link: (String, String)? = nil
    }

    private let steps: [Step] = [
        Step(id: 1, icon: "key.fill", tint: Theme.accent,
             title: "API-sleutel aanmaken",
             summary: "Een teamsleutel in App Store Connect",
             lines: [
                "Open App Store Connect en log in met je Apple-account (Account Holder of Admin).",
                "Ga naar Gebruikers en toegang → tabblad Integraties.",
                "Kies links App Store Connect API en dan Teamsleutels.",
                "Eerste keer? Tik op Vraag toegang aan en accepteer de voorwaarden.",
                "Tik op + (Genereer API-sleutel), geef een naam zoals ‘DevTools’ en kies de rol Admin.",
                "Tik op Genereer. De sleutel verschijnt in de lijst."
             ],
             link: ("Open Integraties", "https://appstoreconnect.apple.com/access/integrations/api")),
        Step(id: 2, icon: "person.text.rectangle.fill", tint: Theme.cyan,
             title: "Issuer ID kopiëren",
             summary: "Eén ID voor je hele team",
             lines: [
                "Op dezelfde pagina (Teamsleutels) staat bovenaan Issuer ID.",
                "Het is een lange code in de vorm 69a6de7a-xxxx-xxxx-xxxx-xxxxxxxxxxxx.",
                "Tik op Kopieer en plak hem in DevTools bij Issuer ID."
             ]),
        Step(id: 3, icon: "number.square.fill", tint: Theme.pending,
             title: "Key ID",
             summary: "10 tekens, staat in de lijst én in de bestandsnaam",
             lines: [
                "In de lijst met sleutels staat per sleutel een Sleutel-ID (Key ID), bijvoorbeeld 2X9R4HXF34.",
                "Hetzelfde ID zit in de bestandsnaam: AuthKey_2X9R4HXF34.p8.",
                "Kies je in DevTools het .p8-bestand, dan wordt de Key ID automatisch ingevuld."
             ]),
        Step(id: 4, icon: "doc.badge.arrow.up.fill", tint: Theme.review,
             title: ".p8-bestand downloaden",
             summary: "Kan maar één keer – bewaar hem goed",
             lines: [
                "Tik bij je nieuwe sleutel op Download API-sleutel. Apple laat dit maar één keer toe.",
                "Op de Mac: AirDrop het AuthKey_….p8-bestand naar je iPhone en bewaar het in Bestanden, of zet het in iCloud Drive.",
                "In DevTools: Account → Account toevoegen → Kies AuthKey_*.p8.",
                "De sleutel gaat direct de Keychain van dit toestel in. Verwijder daarna gerust de kopie uit Bestanden.",
                "Kwijt? Trek de oude sleutel in en maak een nieuwe aan."
             ]),
        Step(id: 5, icon: "building.columns.fill", tint: Theme.live,
             title: "Vendornummer opzoeken",
             summary: "Nodig voor downloads en opbrengst",
             lines: [
                "Ga in App Store Connect naar Business (bovenin de menubalk).",
                "Onder je naam staat rechts naast je adres een getal van 8 cijfers, bijvoorbeeld 85734756. Dat is je vendornummer.",
                "Vul het in bij Account → je account → Wijzig → Vendornummer.",
                "Apple levert verkoopcijfers ongeveer een dag later; de cijfers van vandaag zie je morgen."
             ],
             link: ("Open Business", "https://appstoreconnect.apple.com/business")),
        Step(id: 6, icon: "person.badge.shield.checkmark.fill", tint: Theme.accent,
             title: "Welke rol heb ik nodig?",
             summary: "Admin geeft toegang tot alles",
             lines: [
                "Apps, versies, teksten, builds en TestFlight: App Manager of Admin.",
                "Downloads, opbrengst (Sales Reports): Sales, Finance of Admin.",
                "Reageren op reviews: Customer Support, App Manager of Admin.",
                "Tip: gebruik één sleutel met de rol Admin, dan werkt alles in DevTools.",
                "De rol van een bestaande sleutel kun je niet wijzigen; maak dan een nieuwe sleutel."
             ]),
        Step(id: 7, icon: "lock.shield.fill", tint: Theme.textSecondary,
             title: "Veiligheid",
             summary: "Je sleutel blijft op dit toestel",
             lines: [
                "De .p8 wordt alleen in de Keychain van dit toestel bewaard en nooit gesynchroniseerd of verstuurd.",
                "DevTools praat rechtstreeks met api.appstoreconnect.apple.com; er zit geen server tussen.",
                "Toestel kwijt? Trek de sleutel in via Integraties → Teamsleutels → Trek in."
             ])
    ]

    private let problems: [(String, String)] = [
        ("401 – Authenticatie mislukt", "Issuer ID of Key ID klopt niet, de .p8 hoort bij een andere sleutel, of de sleutel is ingetrokken."),
        ("403 – Geen toegang", "De rol van de sleutel is te beperkt voor deze actie. Gebruik een sleutel met de rol Admin."),
        ("Geen downloads zichtbaar", "Vendornummer ontbreekt of klopt niet, de sleutel heeft geen Sales-/Finance-rol, of er waren nog geen verkopen (rapporten lopen 1 dag achter)."),
        ("Geen app-iconen", "Iconen komen uit de App Store (live apps) of uit je laatste geüploade build. Upload een build of trek omlaag om te verversen.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                ForEach(steps) { step in stepCard(step) }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Problemen oplossen", systemImage: "wrench.and.screwdriver.fill").font(.headline)
                    ForEach(Array(problems.enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LS(item.element.0)).font(.subheadline.weight(.semibold))
                            Text(LS(item.element.1)).font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .devCard()
                Button { openURL(URL(string: "https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api")!) } label: {
                    Label("Apple-documentatie over API-sleutels", systemImage: "book.fill")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Handleiding")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        HStack(spacing: 14) {
            Image("SplashLogo").resizable().scaledToFit().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Koppelen in 5 minuten").font(.title3.weight(.bold))
                Text("Je hebt nodig: Issuer ID, Key ID, het .p8-bestand en (voor downloads) je vendornummer.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepCard(_ step: Step) -> some View {
        let open = expanded.contains(step.id)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    if open { expanded.remove(step.id) } else { expanded.insert(step.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(step.tint)
                        Image(systemName: step.icon).foregroundStyle(.white).font(.subheadline.weight(.semibold))
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stap \(step.id) · \(LS(step.title))").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(LS(step.summary)).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(step.lines.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(item.offset + 1)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(step.tint)
                                .frame(width: 20, height: 20)
                                .background(step.tint.opacity(0.15), in: Circle())
                            Text(LS(item.element)).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let link = step.link, let url = URL(string: link.1) {
                        Button { openURL(url) } label: {
                            Label(LS(link.0), systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(step.tint)
                        .padding(.top, 2)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .devCard()
    }
}

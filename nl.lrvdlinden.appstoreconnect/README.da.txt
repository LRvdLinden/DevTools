App Store Connect bringer dine iOS-, iPadOS-, macOS- og tvOS-apps ind i Homey.

Tilføj hver app fra din App Store Connect-konto som en enhed, og følg:
• Downloads i går, de sidste 7 dage, de sidste 30 dage og i alt
• Opdateringer og provenu for de sidste 30 dage
• App Store-status (Live, Venter på gennemgang, Under gennemgang, Klar til distribution, Afventer frigivelse, Afvist)
• Live-version, næste version og det seneste TestFlight-build
• Bedømmelse og antal bedømmelser

Enheden "Alle apps" viser totalerne for hele din portefølje: downloads i alt, live-apps, apps under gennemgang og apps, der kræver opmærksomhed.

Flows
• Når: status ændret, sendt til App Review, afvist, klar til distribution, venter på din frigivelse, ny live-version, nyt build, build behandlet, ny kundeanmeldelse, bedømmelse ændret, nye downloadtal, downloads faldet
• Og: app er live, i App Review, ny version i gang, downloads over et antal, bedømmelse over et antal, live-version ældre end X dage
• Så: opdater, frigiv den godkendte version, svar på en kundeanmeldelse

Dashboard-widgets
Downloads (én app eller alle apps, med et diagram i Insights-stil), Topapps og Gennemgang & status – samme design som DevTools-appen til iPhone.

Opsætning: opret en App Store Connect API-teamnøgle (rollen Admin), og indsæt Issuer ID, Key ID og .p8-nøglen i appindstillingerne. Tilføj dit leverandørnummer for at få downloads. En trin-for-trin-vejledning findes i indstillingerne.

Din API-nøgle gemmes kun på din Homey. Denne app er ikke tilknyttet Apple Inc.

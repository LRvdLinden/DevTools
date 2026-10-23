App Store Connect tar in dina iOS-, iPadOS-, macOS- och tvOS-appar i Homey.

Lägg till varje app från ditt App Store Connect-konto som en enhet och följ:
• Nedladdningar igår, senaste 7 dagarna, senaste 30 dagarna och totalt
• Uppdateringar och intäkter de senaste 30 dagarna
• App Store-status (Publicerad, Väntar på granskning, Granskas, Klar för distribution, Väntar på publicering, Avvisad)
• Publicerad version, nästa version och senaste TestFlight-build
• Betyg och antal betyg

Enheten "Alla appar" visar totalerna för hela din portfölj: totala nedladdningar, publicerade appar, appar under granskning och appar som kräver åtgärd.

Flows
• När: status har ändrats, skickad till App Review, avvisad, klar för distribution, väntar på din publicering, ny publicerad version, ny build, build bearbetad, ny kundrecension, betyget har ändrats, nya nedladdningssiffror, nedladdningarna har minskat
• Och: appen är publicerad, i App Review, ny version under arbete, nedladdningar över ett antal, betyg över ett värde, publicerad version äldre än X dagar
• Då: uppdatera, publicera den godkända versionen, svara på en kundrecension

Dashboard-widgetar
Nedladdningar (en app eller alla appar, med ett diagram i Insights-stil), Toppappar och Granskning & status – samma design som DevTools-appen för iPhone.

Konfiguration: skapa en App Store Connect API-teamnyckel (Admin-roll) och klistra in Issuer ID, Key ID och .p8-nyckeln i appinställningarna. Lägg till ditt leverantörsnummer för nedladdningar. En steg-för-steg-guide finns i inställningarna.

Din API-nyckel lagras endast på din Homey. Den här appen är inte ansluten till Apple Inc.

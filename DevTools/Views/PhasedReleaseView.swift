import SwiftUI

/// Phased release (7-day rollout) for an App Store version: turn on before release, then pause, resume or release to everyone.
struct PhasedReleaseSection: View {
    let versionID: String
    let versionState: String
    @Environment(DevStore.self) private var store
    @State private var phased: JRes?
    @State private var loaded = false
    @State private var working = false
    @State private var error: String?
    @State private var confirmAll = false

    static let percentages = [1, 2, 5, 10, 20, 50, 100]

    private var isLive: Bool { versionState == "READY_FOR_SALE" }
    private var canEnable: Bool { !isLive && !AppState.closedStates.contains(versionState) }

    var body: some View {
        Section {
            if let error { Text(error).font(.caption).foregroundStyle(Theme.rejected) }
            if !loaded {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let p = phased {
                let state = p.str("phasedReleaseState")
                let day = max(1, min(7, p.i("currentDayNumber") ?? 1))
                HStack {
                    Text(stateLabel(state)).font(.subheadline.weight(.semibold))
                    Spacer()
                    if state == "ACTIVE" || state == "PAUSED" {
                        Text("Dag \(day) van 7 · \(Self.percentages[day - 1])%").font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
                if state == "ACTIVE" || state == "PAUSED" || state == "COMPLETE" {
                    PhaseBar(day: state == "COMPLETE" ? 7 : day, paused: state == "PAUSED")
                }
                switch state {
                case "INACTIVE":
                    Text("Start automatisch zodra de versie live gaat.").font(.footnote).foregroundStyle(Theme.textSecondary)
                    if canEnable {
                        Button(role: .destructive) { Task { await remove(p) } } label: { Label("Gefaseerde release uitzetten", systemImage: "xmark.circle") }
                            .disabled(working)
                    }
                case "ACTIVE":
                    Button { Task { await set(p, "PAUSED") } } label: { Label("Pauzeer release", systemImage: "pause.circle.fill") }.disabled(working)
                    Button { confirmAll = true } label: { Label("Nu aan iedereen uitbrengen", systemImage: "person.3.sequence.fill") }.disabled(working)
                case "PAUSED":
                    Text("Gepauzeerd. Nieuwe gebruikers kunnen de versie nog wel handmatig downloaden. Je kunt maximaal 30 dagen pauzeren.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    Button { Task { await set(p, "ACTIVE") } } label: { Label("Hervat release", systemImage: "play.circle.fill") }.disabled(working)
                    Button { confirmAll = true } label: { Label("Nu aan iedereen uitbrengen", systemImage: "person.3.sequence.fill") }.disabled(working)
                default:
                    Text("Deze versie is aan alle gebruikers uitgebracht.").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } else if canEnable {
                Text("Verspreid de automatische update over 7 dagen (1%, 2%, 5%, 10%, 20%, 50%, 100%). Iedereen kan de versie wel direct handmatig downloaden.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                Button { Task { await enable() } } label: { Label("Gefaseerde release aanzetten", systemImage: "chart.line.uptrend.xyaxis") }.disabled(working)
            } else {
                Text("Geen gefaseerde release voor deze versie.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        } header: { Text("Gefaseerde release") }
        .cardRows()
        .task(id: versionID) { await load() }
        .confirmationDialog("Nu aan iedereen uitbrengen?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Uitbrengen aan iedereen") { if let p = phased { Task { await set(p, "COMPLETE") } } }
        } message: { Text("Alle gebruikers met automatische updates krijgen deze versie. Dit kan niet teruggedraaid worden.") }
    }

    private func stateLabel(_ s: String) -> String {
        switch s {
        case "INACTIVE": return L("Aan, nog niet gestart")
        case "ACTIVE": return L("Bezig")
        case "PAUSED": return L("Gepauzeerd")
        case "COMPLETE": return L("Afgerond")
        default: return Pretty.label(s)
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        do {
            phased = try await api.jget("/v1/appStoreVersions/\(versionID)/appStoreVersionPhasedRelease").data.first
            error = nil
        } catch let e as ConnectError where e.status == 404 {
            phased = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    private func perform(_ op: () async throws -> Void) async {
        working = true
        defer { working = false }
        do { try await op(); error = nil; await load() }
        catch { self.error = error.localizedDescription }
    }

    private func enable() async {
        guard let api = store.api else { return }
        await perform {
            try await api.jcreate("/v1/appStoreVersionPhasedReleases", type: "appStoreVersionPhasedReleases",
                                  attributes: ["phasedReleaseState": "INACTIVE"],
                                  relationships: ["appStoreVersion": ("appStoreVersions", versionID)])
        }
    }

    private func set(_ p: JRes, _ state: String) async {
        guard let api = store.api else { return }
        await perform { try await api.jpatch("/v1/appStoreVersionPhasedReleases/\(p.id)", type: "appStoreVersionPhasedReleases", id: p.id, attributes: ["phasedReleaseState": state]) }
    }

    private func remove(_ p: JRes) async {
        guard let api = store.api else { return }
        await perform { try await api.jdelete("/v1/appStoreVersionPhasedReleases/\(p.id)") }
    }
}

/// Seven segments, filled up to the current day.
struct PhaseBar: View {
    let day: Int
    var paused = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { d in
                VStack(spacing: 3) {
                    Capsule()
                        .fill(d <= day ? (paused ? Theme.review : Theme.live) : Theme.cardRaised)
                        .frame(height: 6)
                    Text("\(PhasedReleaseSection.percentages[d - 1])%").font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

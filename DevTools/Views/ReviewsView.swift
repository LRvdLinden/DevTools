import SwiftUI
import Charts

struct ReviewsView: View {
    let app: AppSummary
    @Environment(DevStore.self) private var store
    @State private var reviews: [ConnectAPI.ReviewItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var stars: Int = 0
    @State private var onlyUnanswered = false
    @State private var replyTarget: ConnectAPI.ReviewItem?
    @State private var feedback: String?

    struct StarCount: Identifiable {
        let stars: Int
        let count: Int
        var id: Int { stars }
    }

    private var filtered: [ConnectAPI.ReviewItem] {
        reviews.filter { r in
            (stars == 0 || r.rating == stars) && (!onlyUnanswered || r.response == nil)
        }
    }

    private var distribution: [StarCount] {
        (1...5).reversed().map { s in StarCount(stars: s, count: reviews.filter { $0.rating == s }.count) }
    }

    var body: some View {
        List {
            if let error { ErrorBanner(message: error).listRowBackground(Color.clear) }
            if !reviews.isEmpty {
                Section {
                    HStack(alignment: .center, spacing: 18) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", average)).font(.system(size: 44, weight: .bold, design: .rounded))
                            Text("\(reviews.count) reviews").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Chart(distribution) { d in
                            BarMark(x: .value("Aantal", d.count), y: .value("Sterren", "\(d.stars)★"))
                                .foregroundStyle(Color.yellow.gradient)
                                .cornerRadius(3)
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 110)
                    }
                    .padding(.vertical, 4)
                    Picker("Sterren", selection: $stars) {
                        Text("Alle").tag(0)
                        ForEach((1...5).reversed(), id: \.self) { Text("\($0)★").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Alleen zonder reactie", isOn: $onlyUnanswered)
                }
                .cardRows()
            }
            Section {
                ForEach(filtered) { r in
                    ReviewCell(review: r) { replyTarget = r } onDelete: { Task { await deleteResponse(r) } }
                }
            }
            .cardRows()
        }
        .themedList()
        .overlay {
            if loading && reviews.isEmpty { ProgressView() }
            else if !loading && reviews.isEmpty && error == nil { ContentUnavailableView("Nog geen reviews", systemImage: "star.bubble") }
        }
        .navigationTitle("Beoordelingen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $replyTarget) { r in
            ReplySheet(review: r) { text in await reply(r, text) }
        }
        .actionFeedback($feedback)
    }

    private var average: Double {
        guard !reviews.isEmpty else { return 0 }
        return Double(reviews.reduce(0) { $0 + $1.rating }) / Double(reviews.count)
    }

    private func load() async {
        guard let api = store.api else { return }
        loading = true
        defer { loading = false }
        do { reviews = try await api.reviews(appID: app.id); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func reply(_ r: ConnectAPI.ReviewItem, _ text: String) async -> Bool {
        guard let api = store.api else { return false }
        do {
            if let existing = r.responseID { try await api.deleteResponse(existing) }
            try await api.respond(toReview: r.id, text: text)
            feedback = "Reactie geplaatst — Apple publiceert hem na controle"
            await load()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func deleteResponse(_ r: ConnectAPI.ReviewItem) async {
        guard let api = store.api, let id = r.responseID else { return }
        do { try await api.deleteResponse(id); feedback = "Reactie verwijderd"; await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct ReviewCell: View {
    let review: ConnectAPI.ReviewItem
    var onReply: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= review.rating ? "star.fill" : "star").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                Spacer()
                Text("\(Fmt.flag(Territory.alpha2(review.territory))) \(Fmt.day(review.date))").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            if !review.title.isEmpty { Text(review.title).font(.subheadline.weight(.semibold)) }
            Text(review.body).font(.callout)
            Text(review.nickname).font(.caption).foregroundStyle(Theme.textSecondary)
            if let response = review.response {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Jouw reactie", systemImage: "arrowshape.turn.up.left.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        if let state = review.responseState, state != "PUBLISHED" {
                            Text(state == "PENDING_PUBLISH" ? "wacht op publicatie" : state.lowercased()).font(.caption2).foregroundStyle(Theme.review)
                        }
                    }
                    Text(response).font(.footnote)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button(action: onReply) {
                    Label(review.response == nil ? "Reageren" : "Reactie bewerken", systemImage: "arrowshape.turn.up.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if review.response != nil {
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct ReplySheet: View {
    let review: ConnectAPI.ReviewItem
    var send: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    Text(review.title).font(.subheadline.weight(.semibold))
                    Text(review.body).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Section {
                    LimitedTextEditor(title: "Je reactie", text: $text, limit: 5970, minHeight: 160)
                } footer: { Text("Reacties zijn openbaar zichtbaar in de App Store.") }
            }
            .navigationTitle("Reageren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("Plaats") {
                            Task {
                                sending = true
                                let ok = await send(text)
                                sending = false
                                if ok { dismiss() }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { text = review.response ?? "" }
        }
    }
}

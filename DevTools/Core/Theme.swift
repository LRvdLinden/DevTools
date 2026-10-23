import SwiftUI
import UIKit

/// DevTools visual language: the dark Developer-Tools surface used by HomeyDev
/// (#121319 background, #222329 cards, 10pt radius) combined with the blue → cyan
/// gradient of the DevTools app icon. Every colour has a light and a dark variant.
enum Theme {
    static let accent = Color(light: 0x0A6CFF, dark: 0x2F8BFF)
    static let cyan = Color(light: 0x14B8E6, dark: 0x3CD3FF)
    static let background = Color(light: 0xF2F4F8, dark: 0x111318)
    static let card = Color(light: 0xFFFFFF, dark: 0x1F2128)
    static let cardRaised = Color(light: 0xF6F7FA, dark: 0x292B33)
    static let separator = Color(light: 0xE3E5EA, dark: 0x30323B)
    static let textSecondary = Color(light: 0x6B6E78, dark: 0x9A9DA8)

    static let live = Color(light: 0x1FA851, dark: 0x34D46A)
    static let review = Color(light: 0xF08A00, dark: 0xFFA733)
    static let rejected = Color(light: 0xE5343A, dark: 0xFF5A5F)
    static let pending = Color(light: 0x7A5CFA, dark: 0x9B85FF)

    static let brandGradient = LinearGradient(
        colors: [Color(light: 0x0A4FE0, dark: 0x0A4FE0), Color(light: 0x18B7F2, dark: 0x18B7F2)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let buttonGradient = LinearGradient(
        colors: [Color(light: 0x2F6BFF, dark: 0x2F6BFF), Color(light: 0x21C8F0, dark: 0x21C8F0)],
        startPoint: .leading, endPoint: .trailing
    )

    /// Chart palette (distinct in light and dark).
    static let series: [Color] = [
        Color(light: 0x0A6CFF, dark: 0x3D95FF),
        Color(light: 0x13B5D9, dark: 0x3CD3FF),
        Color(light: 0x7A5CFA, dark: 0x9B85FF),
        Color(light: 0xF08A00, dark: 0xFFA733),
        Color(light: 0x1FA851, dark: 0x34D46A),
        Color(light: 0xE5346E, dark: 0xFF6B95)
    ]
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }

    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("Automatisch (toestel)")
        case .light: return L("Licht")
        case .dark: return L("Donker")
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct DevCard: ViewModifier {
    var padding: CGFloat = 16
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.05), radius: scheme == .dark ? 12 : 8, y: 4)
    }
}

struct GradientPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.buttonGradient, in: Capsule())
            .shadow(color: Theme.cyan.opacity(0.35), radius: 12, y: 6)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension View {
    func devCard(padding: CGFloat = 16) -> some View { modifier(DevCard(padding: padding)) }

    func themedList() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }

    func cardRows() -> some View { listRowBackground(Theme.card) }
}

// MARK: - Formatting

enum Fmt {
    static func number(_ n: Int) -> String { n.formatted(.number) }
    static func compact(_ n: Int) -> String { n.formatted(.number.notation(.compactName)) }
    static func signed(_ n: Int) -> String { n > 0 ? "+" + number(n) : number(n) }
    static func money(_ v: Double, _ currency: String) -> String {
        guard !currency.isEmpty else { return String(format: "%.2f", v) }
        return v.formatted(.currency(code: currency).precision(.fractionLength(v >= 1000 ? 0 : 2)))
    }
    static func relative(_ d: Date?) -> String {
        guard let d else { return "—" }
        return d.formatted(.relative(presentation: .named))
    }
    static func date(_ d: Date?) -> String { d?.formatted(date: .abbreviated, time: .shortened) ?? "—" }
    static func day(_ d: Date?) -> String { d?.formatted(date: .abbreviated, time: .omitted) ?? "—" }
    static func percent(_ v: Double) -> String { v.formatted(.percent.precision(.fractionLength(0))) }

    static func flag(_ country: String) -> String {
        let base: UInt32 = 127397
        var s = ""
        for scalar in country.uppercased().unicodeScalars {
            if let f = UnicodeScalar(base + scalar.value) { s.unicodeScalars.append(f) }
        }
        return s
    }

    static func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

// MARK: - Components

struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String = "number"
    var tint: Color = Theme.accent
    var footnote: String? = nil
    var footnoteColor: Color = Theme.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(LS(title), systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let footnote {
                Text(LS(footnote))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(footnoteColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// App icon loaded from Apple's CDN (build icon asset or App Store artwork), cached in memory.
struct AppIconView: View {
    let url: URL?
    var size: CGFloat = 44
    var name: String = ""

    var body: some View {
        RemoteImage(url: url) {
            ZStack {
                Theme.brandGradient
                if let first = name.first {
                    Text(String(first)).font(.system(size: size * 0.42, weight: .bold, design: .rounded)).foregroundStyle(.white)
                } else {
                    Image(systemName: "app.dashed").foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

@MainActor
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSURL, UIImage>()
    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        if let cached = ImageMemoryCache.shared.image(for: url) { image = cached; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                ImageMemoryCache.shared.store(img, for: url)
                withAnimation(.easeOut(duration: 0.2)) { image = img }
            }
        } catch {}
    }
}

/// Coloured status badge. App Store "Ready for Sale" / "Ready for Distribution" is shown as Live.
struct StateBadge: View {
    let state: String
    var compact = false

    var body: some View {
        if !state.isEmpty && state != "—" {
            let info = AppState.info(for: state)
            HStack(spacing: 4) {
                if !compact { Circle().fill(info.color).frame(width: 6, height: 6) }
                Text(info.label)
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(info.color.opacity(0.15), in: Capsule())
            .foregroundStyle(info.color)
            .lineLimit(1)
            .fixedSize()
        }
    }
}

enum AppState {
    struct Info { let label: String; let color: Color }

    static let liveStates: Set<String> = ["READY_FOR_SALE"]
    static let reviewStates: Set<String> = ["WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW", "WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW"]
    static let editableStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW"]
    static let closedStates: Set<String> = ["READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION", "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE", "REMOVED_FROM_DISTRIBUTION"]

    static func isLive(_ s: String) -> Bool { liveStates.contains(s) }
    static func isReview(_ s: String) -> Bool { reviewStates.contains(s) }

    static func info(for raw: String) -> Info {
        switch raw {
        case "READY_FOR_SALE": return Info(label: L("Live"), color: Theme.live)
        case "READY_FOR_DISTRIBUTION": return Info(label: L("Klaar voor distributie"), color: Theme.cyan)
        case "WAITING_FOR_REVIEW": return Info(label: L("Wacht op review"), color: Theme.review)
        case "IN_REVIEW": return Info(label: L("In review"), color: Theme.review)
        case "READY_FOR_REVIEW": return Info(label: L("Klaar voor review"), color: Theme.review)
        case "PREPARE_FOR_SUBMISSION": return Info(label: L("Voorbereiden"), color: Theme.accent)
        case "PENDING_DEVELOPER_RELEASE": return Info(label: L("Klaar voor release"), color: Theme.pending)
        case "PENDING_APPLE_RELEASE": return Info(label: L("Wacht op Apple"), color: Theme.pending)
        case "ACCEPTED": return Info(label: L("Goedgekeurd"), color: Theme.live)
        case "PROCESSING_FOR_APP_STORE", "PROCESSING_FOR_DISTRIBUTION", "PROCESSING": return Info(label: L("Verwerken"), color: Theme.review)
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "BETA_REJECTED": return Info(label: L("Afgewezen"), color: Theme.rejected)
        case "DEVELOPER_REJECTED": return Info(label: L("Teruggetrokken"), color: Theme.textSecondary)
        case "WAITING_FOR_EXPORT_COMPLIANCE", "MISSING_EXPORT_COMPLIANCE": return Info(label: L("Export compliance"), color: Theme.review)
        case "REPLACED_WITH_NEW_VERSION": return Info(label: L("Vervangen"), color: Theme.textSecondary)
        case "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE", "REMOVED_FROM_DISTRIBUTION": return Info(label: L("Niet beschikbaar"), color: Theme.textSecondary)
        case "PENDING_CONTRACT": return Info(label: L("Contract nodig"), color: Theme.review)
        // Builds / TestFlight
        case "VALID": return Info(label: L("Gereed"), color: Theme.live)
        case "FAILED", "INVALID": return Info(label: L("Mislukt"), color: Theme.rejected)
        case "EXPIRED": return Info(label: L("Verlopen"), color: Theme.textSecondary)
        case "READY_FOR_BETA_TESTING": return Info(label: L("Klaar om te testen"), color: Theme.accent)
        case "IN_BETA_TESTING": return Info(label: L("In test"), color: Theme.live)
        case "READY_FOR_BETA_SUBMISSION": return Info(label: L("Klaar voor beta-review"), color: Theme.accent)
        case "WAITING_FOR_BETA_REVIEW": return Info(label: L("Wacht op beta-review"), color: Theme.review)
        case "IN_BETA_REVIEW": return Info(label: L("In beta-review"), color: Theme.review)
        case "BETA_APPROVED": return Info(label: L("Beta goedgekeurd"), color: Theme.live)
        case "IN_EXPORT_COMPLIANCE_REVIEW": return Info(label: L("Compliance review"), color: Theme.review)
        case "PROCESSING_EXCEPTION": return Info(label: L("Fout bij verwerken"), color: Theme.rejected)
        case "NOT_IN_TESTING": return Info(label: L("Niet in test"), color: Theme.textSecondary)
        // Review submissions
        case "UNRESOLVED_ISSUES": return Info(label: L("Problemen"), color: Theme.rejected)
        case "CANCELING": return Info(label: L("Annuleren…"), color: Theme.textSecondary)
        case "COMPLETING", "COMPLETE": return Info(label: L("Afgerond"), color: Theme.live)
        default:
            return Info(label: raw.replacingOccurrences(of: "_", with: " ").capitalized, color: Theme.textSecondary)
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.review)
            Text(LS(message)).font(.footnote).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            if let retry { Button("Opnieuw", action: retry).font(.footnote.weight(.semibold)) }
        }
        .padding(12)
        .background(Theme.review.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(Theme.accent) }
            VStack(alignment: .leading, spacing: 2) {
                Text(LS(title)).font(.headline)
                if let subtitle { Text(LS(subtitle)).font(.caption).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Toast-like feedback for actions.
struct ActionFeedback: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(LS(message))
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.spring, value: message)
    }
}

extension View {
    func actionFeedback(_ message: Binding<String?>) -> some View { modifier(ActionFeedback(message: message)) }
}

/// Text field with a live character counter and limit, used for App Store texts.
struct LimitedTextEditor: View {
    let title: String
    @Binding var text: String
    let limit: Int
    var minHeight: CGFloat = 90
    var singleLine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LS(title)).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(text.count)/\(limit)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(text.count > limit ? Theme.rejected : Theme.textSecondary)
            }
            if singleLine {
                TextField(LS(title), text: $text, axis: .vertical)
                    .lineLimit(1...3)
            } else {
                TextEditor(text: $text)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }
}

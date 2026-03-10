import SwiftUI

// MARK: - CBStyle

struct CBStyle {
    static let borderWidth: CGFloat = 2
    static let shadowOffset: CGFloat = 3
    static let cardPadding: CGFloat = 12
    static let pagePadding: CGFloat = 12
    static let cornerRadius: CGFloat = 0
    static let tabBarSpacing: CGFloat = 14

    // MARK: Typography

    struct Fonts {
        static let h1 = Font.system(size: 20, weight: .black, design: .monospaced)
        static let h2 = Font.system(size: 16, weight: .bold, design: .monospaced)
        static let h3 = Font.system(size: 14, weight: .semibold, design: .monospaced)
        static let body = Font.system(size: 13, weight: .regular, design: .monospaced)
        static let bodyMedium = Font.system(size: 13, weight: .medium, design: .monospaced)
        static let caption = Font.system(size: 10, weight: .medium, design: .monospaced)
        static let crypto = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let cryptoMedium = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let badge = Font.system(size: 9, weight: .bold, design: .monospaced)
        static let tiny = Font.system(size: 8, weight: .regular, design: .monospaced)
        static let tinyMedium = Font.system(size: 8, weight: .medium, design: .monospaced)
        static let sectionFooter = Font.system(size: 10, design: .monospaced)
    }

    // MARK: Colors

    struct Colors {
        static let indigo = Color("AccentIndigo", bundle: nil)
        static let amber = Color("AccentAmber", bundle: nil)
        static let emerald = Color("AccentEmerald", bundle: nil)
        static let danger = Color("AccentDanger", bundle: nil)
        static let publicData = Color("PublicData", bundle: nil)
        static let secretData = Color("SecretData", bundle: nil)

        // Fallback colors when asset catalog entries don't exist
        static let indigoFallback = Color(red: 99/255, green: 102/255, blue: 241/255)
        static let amberFallback = Color(red: 245/255, green: 158/255, blue: 11/255)
        static let emeraldFallback = Color(red: 16/255, green: 185/255, blue: 129/255)
        static let dangerFallback = Color(red: 239/255, green: 68/255, blue: 68/255)

        // Semantic aliases
        static var primary: Color { .accentColor }
        static var success: Color { emeraldFallback }
        static var warning: Color { amberFallback }
        static var error: Color { dangerFallback }
        static var party0: Color { indigoFallback }
        static var party1: Color { amberFallback }
    }
}

// MARK: - View Modifiers

struct BrutalistCard: ViewModifier {
    var padding: CGFloat = CBStyle.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            #if os(iOS)
            .background(Color(.systemBackground))
            #else
            .background(Color(.windowBackgroundColor))
            #endif
            .overlay(
                Rectangle()
                    .stroke(Color.primary, lineWidth: CBStyle.borderWidth)
            )
            .shadow(color: .primary.opacity(0.15), radius: 0, x: CBStyle.shadowOffset, y: CBStyle.shadowOffset)
    }
}

struct BrutalistButtonStyle: ButtonStyle {
    var color: Color = .accentColor
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CBStyle.Fonts.badge)
            .textCase(.uppercase)
            .tracking(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .background(isDestructive ? CBStyle.Colors.error : color)
            .overlay(
                Rectangle()
                    .stroke(Color.primary.opacity(0.3), lineWidth: 1)
            )
            .shadow(
                color: .primary.opacity(configuration.isPressed ? 0 : 0.2),
                radius: 0,
                x: configuration.isPressed ? 0 : CBStyle.shadowOffset,
                y: configuration.isPressed ? 0 : CBStyle.shadowOffset
            )
            .offset(
                x: configuration.isPressed ? CBStyle.shadowOffset : 0,
                y: configuration.isPressed ? CBStyle.shadowOffset : 0
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct BrutalistSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CBStyle.Fonts.badge)
            .textCase(.uppercase)
            .tracking(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
            #if os(iOS)
            .background(Color(.systemBackground))
            #else
            .background(Color(.windowBackgroundColor))
            #endif
            .overlay(
                Rectangle()
                    .stroke(Color.primary, lineWidth: CBStyle.borderWidth)
            )
            .shadow(
                color: .primary.opacity(configuration.isPressed ? 0 : 0.15),
                radius: 0,
                x: configuration.isPressed ? 0 : CBStyle.shadowOffset,
                y: configuration.isPressed ? 0 : CBStyle.shadowOffset
            )
            .offset(
                x: configuration.isPressed ? CBStyle.shadowOffset : 0,
                y: configuration.isPressed ? CBStyle.shadowOffset : 0
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func brutalistCard(padding: CGFloat = CBStyle.cardPadding) -> some View {
        modifier(BrutalistCard(padding: padding))
    }
}

// MARK: - Reusable Components

struct StatusBadge: View {
    let label: String
    let status: BadgeStatus

    enum BadgeStatus {
        case ok, fail, pending, info

        var text: String {
            switch self {
            case .ok: return "OK"
            case .fail: return "FAIL"
            case .pending: return "..."
            case .info: return "i"
            }
        }

        var color: Color {
            switch self {
            case .ok: return CBStyle.Colors.success
            case .fail: return CBStyle.Colors.error
            case .pending: return CBStyle.Colors.warning
            case .info: return .blue
            }
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("[\(status.text)]")
                .font(CBStyle.Fonts.badge)
                .foregroundColor(status.color)
            Text(label.uppercased())
                .font(CBStyle.Fonts.badge)
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.1))
    }
}

struct TerminalProgress: View {
    let steps: [(String, Bool)]
    let currentStep: Int

    init(steps: [(String, Bool)]) {
        self.steps = steps
        self.currentStep = steps.firstIndex(where: { !$0.1 }) ?? steps.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 0) {
                    Text("[\(index + 1)/\(steps.count)] ")
                        .font(CBStyle.Fonts.crypto)
                        .foregroundColor(.secondary)
                    Text(step.0)
                        .font(CBStyle.Fonts.crypto)
                        .foregroundColor(step.1 ? .primary : (index == currentStep ? CBStyle.Colors.warning : .secondary))
                    Spacer()
                    if step.1 {
                        Text("[DONE]")
                            .font(CBStyle.Fonts.badge)
                            .foregroundColor(CBStyle.Colors.success)
                    } else if index == currentStep {
                        Text("[...]")
                            .font(CBStyle.Fonts.badge)
                            .foregroundColor(CBStyle.Colors.warning)
                    }
                }
            }
        }
    }
}

struct CryptoDataView: View {
    let label: String
    let value: String
    var isSecret: Bool = false
    var truncate: Int? = 32

    @State private var copied = false

    var displayValue: String {
        guard let truncate = truncate, value.count > truncate else { return value }
        return String(value.prefix(truncate)) + "..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(CBStyle.Fonts.badge)
                    .foregroundColor(.secondary)
                if isSecret {
                    Text("[SECRET]")
                        .font(CBStyle.Fonts.badge)
                        .foregroundColor(CBStyle.Colors.error)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(CBStyle.Colors.error.opacity(0.1))
                } else {
                    Text("[PUBLIC]")
                        .font(CBStyle.Fonts.badge)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                }
            }
            HStack {
                Text(displayValue)
                    .font(CBStyle.Fonts.crypto)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button(action: copyToClipboard) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(copied ? CBStyle.Colors.success : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = value
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(CBStyle.Fonts.crypto)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(CBStyle.Fonts.crypto)
        }
    }
}

struct SectionFooterText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(CBStyle.Fonts.sectionFooter)
    }
}

struct NodeStatusDot: View {
    let color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

struct TagBadge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(CBStyle.Fonts.badge)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
    }
}

struct PlaceholderScreen: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(CBStyle.Fonts.h2)
            Text(description)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            TagBadge(text: "COMING SOON", color: .blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

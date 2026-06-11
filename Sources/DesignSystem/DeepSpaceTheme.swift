import SwiftUI

enum DeepSpaceTheme {
    static let backgroundTop = color(0x05070D)
    static let backgroundMid = color(0x080D1A)
    static let backgroundBottom = color(0x0E1528)
    static let auroraCyan = color(0x6FE7DB)
    static let auroraPurple = color(0x8B7CF6)
    static let amber = color(0xFFB45C)
    static let reviewGreen = color(0x4ADE80)
    static let practiceText = color(0xC7D1E6)
    static let dangerText = color(0xFF8C94)
    static let nearBlackText = color(0x050F1A)
    static let primaryCTAStart = color(0x4FD9C9)
    static let primaryCTAEnd = color(0x338FDB)

    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.64)
    static let tertiaryText = Color.white.opacity(0.45)
    static let glassFill = Color.white.opacity(0.08)
    static let glassStroke = Color.white.opacity(0.12)

    static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct DeepSpaceBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                LinearGradient(
                    stops: [
                        .init(color: DeepSpaceTheme.backgroundTop, location: 0),
                        .init(color: DeepSpaceTheme.backgroundMid, location: 0.60),
                        .init(color: DeepSpaceTheme.backgroundBottom, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(DeepSpaceTheme.auroraCyan.opacity(0.11))
                        .frame(width: 280, height: 280)
                        .blur(radius: 42)
                        .offset(x: -84, y: 96)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(DeepSpaceTheme.auroraPurple.opacity(0.09))
                        .frame(width: 260, height: 260)
                        .blur(radius: 44)
                        .offset(x: 84, y: 128)
                }
                .ignoresSafeArea()
            }
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    var strokeOpacity: Double = 0.12

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(DeepSpaceTheme.glassFill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}

extension View {
    func deepSpaceBackground() -> some View {
        modifier(DeepSpaceBackground())
    }

    func glassCard(cornerRadius: CGFloat = 24, strokeOpacity: Double = 0.12) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }
}

struct AccentChip: View {
    static let height: CGFloat = 24

    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .frame(height: Self.height)
            .background(color.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            )
    }
}

struct PrimaryCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(DeepSpaceTheme.nearBlackText)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                LinearGradient(
                    colors: [DeepSpaceTheme.primaryCTAStart, DeepSpaceTheme.primaryCTAEnd],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
            .shadow(color: DeepSpaceTheme.auroraCyan.opacity(configuration.isPressed ? 0.20 : 0.40), radius: 28, y: 12)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct VoiceBarView: View {
    static let barCount = 5
    static let defaultHeights: [CGFloat] = [12, 20, 28, 20, 12]

    var active = false
    var tint: Color = DeepSpaceTheme.auroraCyan

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill((active ? tint : Color.white).opacity(active ? 0.90 : 0.55))
                    .frame(width: 4, height: Self.defaultHeights[index])
                    .scaleEffect(y: active ? 1.0 : 0.72, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.56)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.06),
                        value: active
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .glassCard(cornerRadius: 28)
    }
}

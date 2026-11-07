import SwiftUI

/// Original, resolution-independent Findaro identity built from native SwiftUI shapes.
struct FindaroMark: View {
    var size: CGFloat = 34
    var showWordmark: Bool = false
    var wordmarkSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.48, blue: 0.92),
                                Color(red: 0.30, green: 0.76, blue: 0.98),
                                Color(red: 0.43, green: 0.39, blue: 0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: max(0.7, size * 0.025))
                VStack(spacing: size * 0.075) {
                    HStack(spacing: size * 0.06) {
                        RoundedRectangle(cornerRadius: size * 0.055)
                            .fill(.white.opacity(0.98))
                            .frame(width: size * 0.42, height: size * 0.12)
                        RoundedRectangle(cornerRadius: size * 0.055)
                            .fill(.white.opacity(0.68))
                            .frame(width: size * 0.18, height: size * 0.12)
                    }
                    RoundedRectangle(cornerRadius: size * 0.055)
                        .fill(.white.opacity(0.88))
                        .frame(width: size * 0.60, height: size * 0.12)
                    RoundedRectangle(cornerRadius: size * 0.055)
                        .fill(.white.opacity(0.62))
                        .frame(width: size * 0.45, height: size * 0.12)
                }
                .rotationEffect(.degrees(-8))
            }
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.25), radius: size * 0.18, y: size * 0.10)

            if showWordmark {
                Text("FINDARO")
                    .font(.system(size: wordmarkSize, weight: .bold, design: .rounded))
                    .tracking(wordmarkSize * 0.055)
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showWordmark ? "Findaro" : "Findaro app")
    }
}

struct FindaroToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, prominent ? 10 : 8)
            .padding(.vertical, 6)
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.42))
            .background(background(configuration.isPressed), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(border.opacity(configuration.isPressed ? 0.8 : 1), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var foreground: Color {
        if destructive { return Color(red: 1.0, green: 0.48, blue: 0.48) }
        if prominent { return .white }
        return .primary.opacity(0.88)
    }

    private var border: Color {
        if destructive { return Color.red.opacity(0.24) }
        if prominent { return OrdenTheme.accent.opacity(0.34) }
        return OrdenTheme.hairline
    }

    private func background(_ pressed: Bool) -> AnyShapeStyle {
        if destructive {
            return AnyShapeStyle(Color.red.opacity(pressed ? 0.19 : 0.10))
        }
        if prominent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        OrdenTheme.accent.opacity(pressed ? 0.95 : 0.82),
                        OrdenTheme.accentSecondary.opacity(pressed ? 0.95 : 0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(OrdenTheme.elevatedFill.opacity(pressed ? 0.95 : 0.72))
    }
}

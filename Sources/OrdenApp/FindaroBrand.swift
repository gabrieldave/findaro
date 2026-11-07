import SwiftUI

/// Compact commercial mark: SF Symbol + wordmark only.
/// Creative direction v1.1 forbids drawing logos in SwiftUI or inventing icon art in code.
/// The Dock/app icon remains the installed PNG/ICNS asset until direction delivers a final PNG.
struct FindaroMark: View {
    var size: CGFloat = 28
    var showWordmark: Bool = true
    var wordmarkSize: CGFloat = 15
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: "folder.badge.magnifyingglass")
                .font(.system(size: size * 0.62, weight: .semibold))
                .foregroundStyle(OrdenTheme.accent)
                .symbolRenderingMode(.hierarchical)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
                        .fill(OrdenTheme.elevatedFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
                        .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
                )

            if showWordmark {
                VStack(alignment: .leading, spacing: 1) {
                    Text("FINDARO")
                        .font(.system(size: wordmarkSize, weight: .bold))
                        .tracking(wordmarkSize * 0.08)
                        .foregroundStyle(.primary)
                    if !compact {
                        Text("Archivos")
                            .font(.system(size: max(9, wordmarkSize * 0.58), weight: .medium))
                            .foregroundStyle(OrdenTheme.textMuted)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Findaro")
    }
}

struct FindaroToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    var destructive = false
    var smart = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, prominent || smart ? 10 : 8)
            .padding(.vertical, 6)
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.42))
            .background(background(configuration.isPressed), in: RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
                    .strokeBorder(border.opacity(configuration.isPressed ? 0.8 : 1), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: OrdenTheme.motionMicro), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
    }

    private var foreground: Color {
        if destructive { return OrdenTheme.danger }
        if prominent || smart { return .white }
        return .primary.opacity(0.88)
    }

    private var border: Color {
        if destructive { return OrdenTheme.danger.opacity(0.28) }
        if smart { return OrdenTheme.accentSecondary.opacity(0.35) }
        if prominent { return OrdenTheme.accent.opacity(0.34) }
        return OrdenTheme.hairline
    }

    private func background(_ pressed: Bool) -> AnyShapeStyle {
        if destructive {
            return AnyShapeStyle(OrdenTheme.danger.opacity(pressed ? 0.20 : 0.10))
        }
        if smart {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        OrdenTheme.accentSecondary.opacity(pressed ? 0.98 : 0.88),
                        OrdenTheme.accent.opacity(pressed ? 0.90 : 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        if prominent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        OrdenTheme.accentHover.opacity(pressed ? 1 : 0.95),
                        OrdenTheme.accent.opacity(pressed ? 0.95 : 0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(OrdenTheme.elevatedFill.opacity(pressed ? 0.95 : 0.78))
    }
}

enum FindaroStatusKind {
    case idle
    case processing
    case success
    case warning
    case error

    var tint: Color {
        switch self {
        case .idle: return OrdenTheme.textMuted
        case .processing: return OrdenTheme.accent
        case .success: return OrdenTheme.success
        case .warning: return OrdenTheme.warning
        case .error: return OrdenTheme.danger
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "circle"
        case .processing: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

struct FindaroStatusPill: View {
    let title: String
    var kind: FindaroStatusKind = .idle

    var body: some View {
        Label(title, systemImage: kind.symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(kind.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(kind.tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(kind.tint.opacity(0.28), lineWidth: 1))
            .accessibilityLabel(title)
    }
}

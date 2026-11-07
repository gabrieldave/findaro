import AppKit
import SwiftUI

/// Compact commercial mark: approved AppIcon asset + wordmark.
/// Creative direction v1.1 forbids inventing logo art in code — use Resources/AppIcon.icns.
struct FindaroMark: View {
    var size: CGFloat = 28
    var showWordmark: Bool = true
    var wordmarkSize: CGFloat = 15
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            brandGlyph
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous))
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

    @ViewBuilder
    private var brandGlyph: some View {
        if let icon = Self.loadBrandIcon() {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            // Fallback visible si el .icns no está en el bundle (solo dev).
            Image(systemName: "magnifyingglass")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(OrdenTheme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
                        .fill(OrdenTheme.elevatedFill)
                )
        }
    }

    /// AppIcon del bundle empaquetado, o Resources/ en el árbol fuente.
    private static func loadBrandIcon() -> NSImage? {
        if let named = NSImage(named: "AppIcon"), named.size.width > 0 {
            return named
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let candidates = [
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/AppIcon.icns"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/AppIcon.icns"),
        ]
        for url in candidates {
            if let img = NSImage(contentsOf: url), img.size.width > 0 {
                return img
            }
        }
        return nil
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

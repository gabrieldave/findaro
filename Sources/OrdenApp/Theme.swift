import SwiftUI
import AppKit

/// Findaro visual system (brand tokens v1.1). Internal type name retained to avoid
/// destabilizing the existing view tree while the commercial rebrand is rolled out.
enum OrdenTheme {
    // MARK: - Brand accents (stable across appearances)

    static let accent = Color(findaroHex: "#2563EB")
    static let accentHover = Color(findaroHex: "#3B82F6")
    static let accentSecondary = Color(findaroHex: "#7C3AED")
    static let cyan = Color(findaroHex: "#22D3EE")
    static let success = Color(findaroHex: "#10B981")
    static let warning = Color(findaroHex: "#F59E0B")
    static let danger = Color(findaroHex: "#EF4444")
    static let selection = Color(findaroHex: "#1E3A8A")

    // MARK: - Surfaces (adaptive)

    static var windowFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#0B1220")
            }
            return NSColor(findaroHex: "#F3F6FB")
        })
    }

    static var sidebarFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#0B1220")
            }
            return NSColor(findaroHex: "#E8EEF7")
        })
    }

    static var panelFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#141F32")
            }
            return NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.96)
        })
    }

    static var elevatedFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#1E2D46")
            }
            return NSColor(findaroHex: "#FFFFFF")
        })
    }

    static var hairline: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#2B3D59").withAlphaComponent(0.95)
            }
            return NSColor(findaroHex: "#C5D0E0").withAlphaComponent(0.9)
        })
    }

    static var textSecondary: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#AEBBD0")
            }
            return NSColor(findaroHex: "#5B6B82")
        })
    }

    static var textMuted: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#7F8DA5")
            }
            return NSColor(findaroHex: "#8090A6")
        })
    }

    static var rowSelectionFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#1E3A8A").withAlphaComponent(0.55)
            }
            return NSColor(findaroHex: "#2563EB").withAlphaComponent(0.16)
        })
    }

    static var sidebarActiveFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(findaroHex: "#2563EB").withAlphaComponent(0.28)
            }
            return NSColor(findaroHex: "#2563EB").withAlphaComponent(0.18)
        })
    }

    // MARK: - Radii (brand tokens)

    static let radiusWindow: CGFloat = 14
    static let radiusPanel: CGFloat = 10
    static let radiusControl: CGFloat = 7
    static let radiusChip: CGFloat = 6

    // MARK: - Motion

    static let motionMicro: Double = 0.10
    static let motionStandard: Double = 0.16
    static let motionEmphasis: Double = 0.22
}

// MARK: - Hex helpers

extension Color {
    init(findaroHex hex: String) {
        self.init(nsColor: NSColor(findaroHex: hex))
    }
}

extension NSColor {
    convenience init(findaroHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255
        self.init(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}

extension View {
    @ViewBuilder
    func ordenGlassCard(cornerRadius: CGFloat = OrdenTheme.radiusWindow) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self
                .padding(12)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .padding(12)
                .background(OrdenTheme.panelFill, in: shape)
                .overlay(shape.strokeBorder(OrdenTheme.hairline, lineWidth: 1))
        }
    }

    func findaroSurface(cornerRadius: CGFloat = OrdenTheme.radiusWindow) -> some View {
        background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
            )
    }

    func findaroPanelChrome(focused: Bool = false, cornerRadius: CGFloat = OrdenTheme.radiusWindow) -> some View {
        background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        focused ? OrdenTheme.accent.opacity(0.85) : OrdenTheme.hairline,
                        lineWidth: focused ? 2 : 1
                    )
            )
    }
}

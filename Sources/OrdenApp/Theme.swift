import SwiftUI
import AppKit

/// Findaro visual system. Internal type name retained to avoid destabilizing
/// the existing view tree while the commercial rebrand is rolled out.
enum OrdenTheme {
    static let accent = Color(red: 0.30, green: 0.72, blue: 1.00)
    static let accentSecondary = Color(red: 0.48, green: 0.43, blue: 1.00)
    static let success = Color(red: 0.30, green: 0.82, blue: 0.66)
    static let warning = Color(red: 1.00, green: 0.69, blue: 0.32)

    static var windowFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedRed: 0.055, green: 0.067, blue: 0.090, alpha: 1)
            }
            return NSColor(calibratedRed: 0.925, green: 0.941, blue: 0.965, alpha: 1)
        })
    }

    static var panelFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedRed: 0.090, green: 0.110, blue: 0.145, alpha: 1)
            }
            return NSColor(calibratedRed: 0.985, green: 0.990, blue: 1.0, alpha: 0.96)
        })
    }

    static var elevatedFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedRed: 0.125, green: 0.150, blue: 0.195, alpha: 1)
            }
            return NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1)
        })
    }

    static var hairline: Color {
        Color.primary.opacity(0.085)
    }

    static var sidebarFill: Color { windowFill }
}

extension View {
    @ViewBuilder
    func ordenGlassCard(cornerRadius: CGFloat = 14) -> some View {
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

    func findaroSurface(cornerRadius: CGFloat = 14) -> some View {
        background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(OrdenTheme.hairline, lineWidth: 1))
    }
}

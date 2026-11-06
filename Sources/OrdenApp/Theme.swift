import SwiftUI
import AppKit

enum OrdenTheme {
    static let accent = Color(red: 0.545, green: 0.612, blue: 1.0)

    /// Un solo fondo para ventana, sidebar y detalle.
    static var windowFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            }
            return NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.96, alpha: 1)
        })
    }

    static var panelFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1)
            }
            return NSColor(calibratedWhite: 1, alpha: 0.92)
        })
    }
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
                .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
        }
    }
}

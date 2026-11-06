import SwiftUI

enum OrdenTheme {
    static let accent = Color(red: 0.545, green: 0.612, blue: 1.0) // lavanda suave

    @ViewBuilder
    static func glassBackground<S: Shape>(in shape: S = RoundedRectangle(cornerRadius: 12, style: .continuous)) -> some View {
        if #available(macOS 26.0, *) {
            shape.fill(.clear)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

extension View {
    /// Fondo tipo Liquid Glass cuando el sistema lo soporta.
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
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

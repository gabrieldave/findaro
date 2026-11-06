import SwiftUI
import OrdenCore

/// Icono fijo por categoría: todos los vídeos se ven igual, todos los Excel igual, etc.
struct FileTypeIcon: View {
    let category: FileCategory
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color(hex: category.tintHex))
            .frame(width: size + 4, height: size + 4, alignment: .center)
            .accessibilityLabel(category.labelSpanish)
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

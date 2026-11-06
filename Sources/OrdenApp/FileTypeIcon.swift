import SwiftUI
import OrdenCore

/// Icono fijo por categoría: mismo tipo → mismo símbolo y color.
struct FileTypeIcon: View {
    let category: FileCategory
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                .fill(Color(hex: category.tintHex).opacity(0.18))
                .frame(width: size + 10, height: size + 10)
            Image(systemName: category.symbolName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color(hex: category.tintHex))
        }
        .accessibilityLabel(category.labelSpanish)
    }
}

extension Color {
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

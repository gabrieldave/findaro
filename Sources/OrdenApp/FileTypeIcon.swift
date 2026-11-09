import SwiftUI
import AppKit
import OrdenCore

/// Icono por categoría. En imagen/vídeo: miniatura + contorno del color del tipo.
struct FileTypeIcon: View {
    let category: FileCategory
    var path: String? = nil
    var size: CGFloat = 16

    @State private var thumb: NSImage?

    private var box: CGFloat { size + 10 }
    private var tint: Color { Color(hex: category.tintHex) }
    /// Tipos donde QL suele dar una previa útil (el contorno sigue siendo el color del tipo).
    private var showsPreview: Bool {
        guard let path, !path.isEmpty else { return false }
        switch category {
        case .image, .video, .pdf, .app, .folder:
            return true
        default:
            return false
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                .fill(tint.opacity(thumb == nil ? 0.18 : 0.08))
                .frame(width: box, height: box)

            if let thumb {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: box - 4, height: box - 4)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))

                if category == .video {
                    // Contorno rojo del tipo + play para no confundirlo con foto.
                    Image(systemName: "play.fill")
                        .font(.system(size: max(8, size * 0.42), weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 1.5, y: 0.5)
                }
            } else {
                Image(systemName: category.symbolName)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .overlay {
            if showsPreview {
                RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                    .strokeBorder(tint, lineWidth: max(1.5, size * 0.08))
            }
        }
        .frame(width: box, height: box)
        .accessibilityLabel(category.labelLocalized)
        .task(id: "\(path ?? "")|\(Int(size))|\(category.rawValue)") {
            guard showsPreview, let path else {
                thumb = nil
                return
            }
            thumb = await ThumbnailStore.shared.thumbnail(for: path, pointSize: box)
        }
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

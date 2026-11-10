import AppKit

/// Arrastre nativo de archivos/carpetas (AppKit) — convive con el marquee de SwiftUI.
/// El modo naranja se arma con ⌘+clic (sticky) y solo se apaga tras drop / Esc.
@MainActor
final class FolderDragBridge: NSObject, NSDraggingSource {
    static let shared = FolderDragBridge()

    private var isDragging = false
    /// `true` si el drop aceptó move/copy; `false` si se canceló.
    var onSessionEnded: ((Bool) -> Void)?

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.move, .copy]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
        let dropped = !operation.isEmpty
        let callback = onSessionEnded
        onSessionEnded = nil
        Task { @MainActor in
            callback?(dropped)
        }
    }

    /// Inicia arrastre de una o varias rutas desde el evento de mouse actual.
    @discardableResult
    func startDrag(paths: [String]) -> Bool {
        guard !isDragging else { return false }
        guard let event = NSApp.currentEvent else { return false }
        guard let view = NSApp.keyWindow?.contentView else { return false }

        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return false }

        let origin = event.locationInWindow
        let badge = Self.simpleMoveBadge(count: urls.count, name: urls[0].lastPathComponent)
        let badgeSize = badge.size
        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            if index == 0 {
                // Un solo indicador sutil bajo el cursor (sin icono de documento negro).
                let rect = NSRect(
                    x: origin.x - badgeSize.width * 0.35,
                    y: origin.y - badgeSize.height * 0.55,
                    width: badgeSize.width,
                    height: badgeSize.height
                )
                item.setDraggingFrame(rect, contents: badge)
            } else {
                // El resto viaja en el pasteboard sin fantasma visual extra.
                item.setDraggingFrame(
                    NSRect(x: origin.x, y: origin.y, width: 1, height: 1),
                    contents: nil
                )
            }
            return item
        }

        isDragging = true
        view.beginDraggingSession(with: items, event: event, source: self)
        return true
    }

    /// Pastilla translúcida: resalta el movimiento sin silueta de archivo.
    private static func simpleMoveBadge(count: Int, name: String) -> NSImage {
        let label: String
        if count > 1 {
            label = "\(min(count, 99))"
        } else {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            label = trimmed.count > 22 ? String(trimmed.prefix(20)) + "…" : trimmed
        }

        let font = NSFont.systemFont(ofSize: count > 1 ? 13 : 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let text = label as NSString
        let textSize = text.size(withAttributes: attrs)
        let padX: CGFloat = count > 1 ? 10 : 12
        let padY: CGFloat = count > 1 ? 8 : 7
        let size = NSSize(
            width: max(count > 1 ? 28 : 72, textSize.width + padX * 2),
            height: max(28, textSize.height + padY * 2)
        )

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2)
        NSColor.controlAccentColor.withAlphaComponent(0.88).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()

        let textOrigin = NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 0.5
        )
        text.draw(at: textOrigin, withAttributes: attrs)
        return image
    }
}

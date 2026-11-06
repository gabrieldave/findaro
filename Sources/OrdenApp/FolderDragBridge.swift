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
        let items: [NSDraggingItem] = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let offset = CGFloat(min(index, 6)) * 5
            let rect = NSRect(
                x: origin.x - 18 + offset,
                y: origin.y - 18 - offset,
                width: 36,
                height: 36
            )
            let image: NSImage
            if index == 0, urls.count > 1 {
                image = Self.stackedBadgeImage(count: urls.count, isDirectory: isDir.boolValue)
            } else {
                let symbol = isDir.boolValue ? "folder.fill" : "doc.fill"
                image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                    ?? NSImage(size: NSSize(width: 32, height: 32))
            }
            item.setDraggingFrame(rect, contents: image)
            return item
        }

        isDragging = true
        view.beginDraggingSession(with: items, event: event, source: self)
        return true
    }

    private static func stackedBadgeImage(count: Int, isDirectory: Bool) -> NSImage {
        let size = NSSize(width: 44, height: 44)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let symbol = isDirectory ? "folder.fill" : "doc.fill"
        if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
            let configured = base.withSymbolConfiguration(conf) ?? base
            let rect = NSRect(x: 4, y: 10, width: 28, height: 28)
            configured.draw(in: rect)
        }

        let badge = NSRect(x: 22, y: 2, width: 20, height: 20)
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let text = "\(min(count, 99))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        text.draw(
            at: NSPoint(
                x: badge.midX - textSize.width / 2,
                y: badge.midY - textSize.height / 2
            ),
            withAttributes: attrs
        )
        return image
    }
}

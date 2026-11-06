import AppKit

/// Arrastre nativo de archivos/carpetas (AppKit) — convive con el marquee de SwiftUI.
/// Tras mantener ~1s sobre un ítem, se arma el arrastre para mover/copiar.
@MainActor
final class FolderDragBridge: NSObject, NSDraggingSource {
    static let shared = FolderDragBridge()

    private var isDragging = false

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Destino elige: en Finder suele ser mover (mismo volumen) o copiar.
        [.move, .copy]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
    }

    /// Inicia arrastre de rutas (archivos o carpetas) desde el evento de mouse actual.
    @discardableResult
    func startDrag(paths: [String]) -> Bool {
        guard !isDragging else { return false }
        guard let event = NSApp.currentEvent else { return false }
        guard let view = NSApp.keyWindow?.contentView else { return false }

        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return false }

        let items: [NSDraggingItem] = urls.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let symbol = isDir.boolValue ? "folder.fill" : "doc.fill"
            let rect = NSRect(
                x: event.locationInWindow.x - 16,
                y: event.locationInWindow.y - 16,
                width: 32,
                height: 32
            )
            item.setDraggingFrame(
                rect,
                contents: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            )
            return item
        }

        isDragging = true
        view.beginDraggingSession(with: items, event: event, source: self)
        return true
    }
}

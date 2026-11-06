import AppKit

/// Arrastre nativo de carpetas (AppKit) — convive con el marquee de SwiftUI.
@MainActor
final class FolderDragBridge: NSObject, NSDraggingSource {
    static let shared = FolderDragBridge()

    private var isDragging = false

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
    }

    /// Inicia arrastre de rutas de carpeta desde el evento de mouse actual.
    @discardableResult
    func startDrag(paths: [String]) -> Bool {
        guard !isDragging else { return false }
        guard let event = NSApp.currentEvent else { return false }
        guard let view = NSApp.keyWindow?.contentView else { return false }
        let urls = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    && isDir.boolValue
            }
        guard !urls.isEmpty else { return false }

        let items: [NSDraggingItem] = urls.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let rect = NSRect(x: event.locationInWindow.x - 16, y: event.locationInWindow.y - 16, width: 32, height: 32)
            item.setDraggingFrame(rect, contents: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil))
            return item
        }

        isDragging = true
        view.beginDraggingSession(with: items, event: event, source: self)
        return true
    }
}

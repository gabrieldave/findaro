import AppKit

/// Esc cancela la selección aunque el foco esté en toolbar/búsqueda.
/// (`.onKeyPress` y el atajo de menú fallan a menudo con Escape en AppKit.)
@MainActor
enum SelectionCancelMonitor {
    private static var keyMonitor: Any?

    static func install(browser: BrowserModel) {
        remove()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event } // Escape
            if isEditingText { return event }
            if NSApp.keyWindow?.attachedSheet != nil { return event }
            if browser.showNewFolderDialog || browser.showRenameDialog { return event }
            browser.cancelSelection()
            return nil
        }
    }

    static func remove() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private static var isEditingText: Bool {
        guard let fr = NSApp.keyWindow?.firstResponder else { return false }
        if fr is NSTextView || fr is NSTextField { return true }
        let name = NSStringFromClass(type(of: fr))
        return name.contains("FieldEditor") || name.contains("TextInput")
    }
}

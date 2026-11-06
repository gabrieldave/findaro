import AppKit

/// Atajos de teclado fiables (AppKit). Los del menú SwiftUI fallan con
/// Option+flechas (llevan flag `.function`) y con foco en la búsqueda.
@MainActor
enum SelectionCancelMonitor {
    private static var keyMonitor: Any?

    static func install(browser: BrowserModel) {
        remove()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if shouldIgnore(event, browser: browser) {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.keyCode
            let chars = event.charactersIgnoringModifiers ?? ""

            let opt = flags.contains(.option)
            let cmd = flags.contains(.command)
            let shift = flags.contains(.shift)
            let ctrl = flags.contains(.control)
            // Las flechas suelen traer `.function` — no exigir igualdad exacta de flags.

            // Esc → cancelar selección
            if key == 53, !opt, !cmd, !shift, !ctrl {
                browser.cancelSelection()
                return nil
            }

            // ⌥← / ⌥→ → atrás / adelante (como Alt+flechas en Windows)
            // Ignoramos `.function` que AppKit pone en las flechas.
            if opt, !cmd, !shift, !ctrl {
                if key == 123 { // left arrow
                    browser.goBack()
                    return nil
                }
                if key == 124 { // right arrow
                    browser.goForward()
                    return nil
                }
            }

            // ⌘[ / ⌘] → atrás / adelante (Finder); keyCodes 33/30 = [ ] en ANSI
            if cmd, !opt, !ctrl {
                if chars == "[" || chars == "{" || (!shift && key == 33) {
                    browser.goBack()
                    return nil
                }
                if chars == "]" || chars == "}" || (!shift && key == 30) {
                    browser.goForward()
                    return nil
                }
            }

            // ⌘↑ → carpeta superior
            if cmd, !opt, !shift, !ctrl, key == 126 {
                browser.goUp()
                return nil
            }

            return event
        }
    }

    static func remove() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private static func shouldIgnore(_ event: NSEvent, browser: BrowserModel) -> Bool {
        if isEditingText { return true }
        if NSApp.keyWindow?.attachedSheet != nil { return true }
        if browser.showNewFolderDialog || browser.showRenameDialog { return true }
        return false
    }

    private static var isEditingText: Bool {
        guard let fr = NSApp.keyWindow?.firstResponder else { return false }
        if fr is NSTextView || fr is NSTextField { return true }
        let name = NSStringFromClass(type(of: fr))
        return name.contains("FieldEditor") || name.contains("TextInput")
    }
}

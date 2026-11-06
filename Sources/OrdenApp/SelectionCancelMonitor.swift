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

            // Esc → cancelar selección múltiple + modo «listo para mover»
            // (ignoramos .function / capsLock que a veces vienen con teclas especiales)
            if key == 53, !opt, !cmd, !shift, !ctrl {
                browser.cancelSelection()
                return nil
            }

            // Espacio → Vista rápida (Quick Look). onKeyPress de SwiftUI no llega
            // con el foco en la lista/scroll; el monitor AppKit sí.
            if key == 49, !opt, !cmd, !shift, !ctrl {
                browser.quickLookSelection()
                return nil
            }

            // Con Vista rápida abierta: ← más nuevo · → más viejo (circular).
            if QuickLookController.shared.isVisible, !opt, !cmd, !shift, !ctrl {
                if key == 123 {
                    QuickLookController.shared.navigate(delta: -1)
                    return nil
                }
                if key == 124 {
                    QuickLookController.shared.navigate(delta: 1)
                    return nil
                }
            }

            // ↑↓ / ←→ → mover selección · ⇧+flechas → extender rango (como Windows).
            // Solo selección; no mueve archivos. Ignora .function de las flechas.
            if !opt, !cmd, !ctrl, (key == 125 || key == 126 || key == 123 || key == 124) {
                if QuickLookController.shared.isVisible, !shift {
                    // ↑↓ con QL abierto: no navegamos la lista (QL usa ←→).
                    if key == 125 || key == 126 {
                        return event
                    }
                } else {
                    let delta: Int
                    switch key {
                    case 126, 123: delta = -1 // ↑ / ←
                    default: delta = 1        // ↓ / →
                    }
                    browser.moveSelectionByKeyboard(delta: delta, extending: shift)
                    return nil
                }
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

            // ⌘1 / ⌘2 / ⌘3 → atrás / adelante / Ir a carpeta (mano izquierda)
            // keyCodes: 18 = 1, 19 = 2, 20 = 3
            // ⌘Z → deshacer movimiento/copia
            // ⌘C / ⌘X / ⌘V → copiar / cortar / pegar archivos
            if cmd, !opt, !ctrl, !shift {
                if chars == "1" || key == 18 {
                    browser.goBack()
                    return nil
                }
                if chars == "2" || key == 19 {
                    browser.goForward()
                    return nil
                }
                if chars == "3" || key == 20 {
                    browser.promptGoToFolder()
                    return nil
                }
                if chars.lowercased() == "z" || key == 6 {
                    browser.undoLastFileOp()
                    return nil
                }
                if chars.lowercased() == "c" || key == 8 {
                    browser.addSelectionToShelf(intent: .copy)
                    return nil
                }
                if chars.lowercased() == "x" || key == 7 {
                    browser.addSelectionToShelf(intent: .move)
                    return nil
                }
                if chars.lowercased() == "v" || key == 9 {
                    browser.pasteFromPasteboard()
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

import AppKit

/// Atajos de teclado fiables (AppKit). Los del menú SwiftUI fallan con
/// Option+flechas (llevan flag `.function`) y con foco en la búsqueda.
@MainActor
enum SelectionCancelMonitor {
    private static var keyMonitor: Any?
    private static var keyUpMonitor: Any?
    private static var flagsMonitor: Any?
    /// Push-to-talk activo por ⌃Espacio (no por el botón del panel).
    private static var voicePTTHeld = false
    private static weak var browserRef: BrowserModel?

    static func install(browser: BrowserModel) {
        remove()
        browserRef = browser
        VoiceCaptureController.shared.onFinished = { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Task { @MainActor in
                guard let browser = SelectionCancelMonitor.browserRef else { return }
                browser.showAssistantPanel = true
                await browser.runAssistant(prompt: trimmed)
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ⌃Espacio (mantener): push-to-talk — también con foco en campos de texto.
            if handleVoicePTTKeyDown(event, browser: browser) {
                return nil
            }

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

            // Esc → búsqueda → otros filtros → selección / modo naranja
            if key == 53, !opt, !cmd, !shift, !ctrl {
                if browser.showDeepSearchPanel {
                    browser.clearDeepSearch()
                    return nil
                }
                if browser.hasActiveViewFilters {
                    browser.resetToNormalView()
                    return nil
                }
                browser.cancelSelection()
                return nil
            }

            // Tab → alternar Origen ↔ Destino (solo dual pane)
            // keyCode 48 = Tab
            if browser.dualPaneEnabled, key == 48, !opt, !cmd, !ctrl {
                browser.toggleFocusedPane()
                return nil
            }

            // ⌘⇧← Origen · ⌘⇧→ Destino
            if browser.dualPaneEnabled, cmd, shift, !opt, !ctrl {
                if key == 123 { // left
                    browser.focusOriginPane()
                    return nil
                }
                if key == 124 { // right
                    browser.focusDestinationPane()
                    return nil
                }
            }

            // ⌘⇧M → mover selección del Origen al Destino
            if browser.dualPaneEnabled, cmd, shift, !opt, !ctrl,
               chars.lowercased() == "m" || key == 46 {
                browser.transferPrimarySelectionToSecondary(copy: false)
                return nil
            }

            // Espacio → Vista rápida (Quick Look). onKeyPress de SwiftUI no llega
            // con el foco en la lista/scroll; el monitor AppKit sí.
            // ⌃Espacio es voz (arriba); aquí solo Espacio solo.
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

            // Return (36): Explorer → abrir; Finder → renombrar
            if key == 36, !opt, !cmd, !shift, !ctrl {
                if browser.explorerKeyboardProfile {
                    browser.openSelection()
                } else if browser.selectedIDs.count == 1 {
                    browser.promptRename()
                }
                return nil
            }

            // F2 (120) → renombrar (perfil Explorer / siempre útil)
            if key == 120, !opt, !cmd, !shift, !ctrl {
                browser.promptRename()
                return nil
            }

            // ⌘L → omnibox de ruta
            if cmd, !opt, !ctrl, !shift, (chars.lowercased() == "l" || key == 37) {
                browser.beginPathOmnibox()
                return nil
            }

            // ⌘⇧. → mostrar/ocultar ocultos
            if cmd, shift, !opt, !ctrl, chars == "." {
                browser.toggleShowHiddenFiles()
                return nil
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

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            if handleVoicePTTKeyUp(event) {
                return nil
            }
            return event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handleVoicePTTFlagsChanged(event)
            return event
        }
    }

    static func remove() {
        if voicePTTHeld {
            endVoicePTT()
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        browserRef = nil
    }

    /// ⌃Espacio: keyDown inicia; keyUp / soltar ⌃ termina.
    private static func handleVoicePTTKeyDown(_ event: NSEvent, browser: BrowserModel) -> Bool {
        guard !event.isARepeat else { return voicePTTHeld }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ctrl = flags.contains(.control)
        let opt = flags.contains(.option)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        // keyCode 49 = Espacio
        guard event.keyCode == 49, ctrl, !opt, !cmd, !shift else { return false }
        if NSApp.keyWindow?.attachedSheet != nil { return false }
        if browser.showOllamaSetupDialog || browser.showFolderHandlerSetupDialog { return false }
        guard !voicePTTHeld else { return true }
        voicePTTHeld = true
        browser.showAssistantPanel = true
        VoiceCaptureController.shared.beginPushToTalk()
        return true
    }

    private static func handleVoicePTTKeyUp(_ event: NSEvent) -> Bool {
        guard voicePTTHeld, event.keyCode == 49 else { return false }
        endVoicePTT()
        return true
    }

    private static func handleVoicePTTFlagsChanged(_ event: NSEvent) {
        guard voicePTTHeld else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.contains(.control) {
            endVoicePTT()
        }
    }

    private static func endVoicePTT() {
        guard voicePTTHeld else { return }
        voicePTTHeld = false
        VoiceCaptureController.shared.endPushToTalk()
    }

    private static func shouldIgnore(_ event: NSEvent, browser: BrowserModel) -> Bool {
        if isEditingText { return true }
        if NSApp.keyWindow?.attachedSheet != nil { return true }
        if browser.showNewFolderDialog
            || browser.showNewFileDialog
            || browser.showRenameDialog
            || browser.showGoToFolderDialog
            || browser.showDeepSearchDialog {
            return true
        }
        return false
    }

    private static var isEditingText: Bool {
        guard let fr = NSApp.keyWindow?.firstResponder else { return false }
        if fr is NSTextView || fr is NSTextField { return true }
        let name = NSStringFromClass(type(of: fr))
        return name.contains("FieldEditor") || name.contains("TextInput")
    }
}

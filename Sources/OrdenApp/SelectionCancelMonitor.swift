import AppKit
import OrdenCore

/// Atajos de teclado fiables (AppKit). Los del menú SwiftUI fallan con
/// Option+flechas (llevan flag `.function`) y con foco en la búsqueda.
/// Las combinaciones se resuelven desde `AppHotkeyCatalog` + preferencias.
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
            if handleVoicePTTKeyDown(event, browser: browser) {
                return nil
            }

            // Enter/Esc en sheets: confirmar o cancelar (SwiftUI .defaultAction falla a menudo).
            if handleModalDialogKeys(event, browser: browser) {
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

            // Preferencias vía store (@unchecked); el monitor corre en el hilo principal.
            let overrides = browser.store.preferences.keyboardHotkeyOverrides
            func hit(_ id: String) -> Bool {
                guard let chord = AppHotkeyCatalog.resolvedChord(id: id, overrides: overrides) else {
                    return false
                }
                return chord.matches(
                    keyCode: key,
                    characters: chars,
                    command: cmd,
                    option: opt,
                    shift: shift,
                    control: ctrl
                )
            }

            // Esc → búsqueda → otros filtros → selección / modo naranja
            if hit("files.cancel") {
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
            if browser.dualPaneEnabled, hit("dual.swapFocus") {
                browser.toggleFocusedPane()
                return nil
            }

            if browser.dualPaneEnabled, hit("dual.focusOrigin") {
                browser.focusOriginPane()
                return nil
            }
            if browser.dualPaneEnabled, hit("dual.focusDest") {
                browser.focusDestinationPane()
                return nil
            }
            if browser.dualPaneEnabled, hit("dual.moveToDest") {
                browser.transferPrimarySelectionToSecondary(copy: false)
                return nil
            }
            if browser.dualPaneEnabled, hit("dual.moveToOrigin") {
                browser.transferSecondarySelectionToPrimary(copy: false)
                return nil
            }

            // Espacio → Vista rápida (⌃Espacio es voz, arriba)
            if hit("files.quickLook") {
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

            // ↑↓ / ←→ → mover selección · ⇧+flechas → extender rango
            if !opt, !cmd, !ctrl, (key == 125 || key == 126 || key == 123 || key == 124) {
                if QuickLookController.shared.isVisible, !shift {
                    if key == 125 || key == 126 {
                        return event
                    }
                } else {
                    let delta: Int
                    switch key {
                    case 126, 123: delta = -1
                    default: delta = 1
                    }
                    browser.moveSelectionByKeyboard(delta: delta, extending: shift)
                    return nil
                }
            }

            if hit("nav.backOption") {
                browser.goBack()
                return nil
            }
            if hit("nav.forwardOption") {
                browser.goForward()
                return nil
            }

            if hit("files.return") {
                if browser.explorerKeyboardProfile {
                    browser.openSelection()
                } else if browser.selectedIDs.count == 1 {
                    browser.promptRename()
                }
                return nil
            }

            if hit("files.renameF2") {
                browser.promptRename()
                return nil
            }

            if hit("nav.omnibox") {
                browser.beginPathOmnibox()
                return nil
            }

            if hit("view.hidden") {
                browser.toggleShowHiddenFiles()
                return nil
            }

            if hit("nav.back") {
                browser.goBack()
                return nil
            }
            if hit("nav.forward") {
                browser.goForward()
                return nil
            }
            if hit("nav.goTo") {
                browser.promptGoToFolder()
                return nil
            }
            if hit("files.undo") {
                browser.undoLastFileOp()
                return nil
            }
            if hit("files.copy") {
                browser.addSelectionToShelf(intent: .copy)
                return nil
            }
            if hit("files.cut") {
                browser.addSelectionToShelf(intent: .move)
                return nil
            }
            if hit("files.paste") {
                browser.pasteFromPasteboard()
                return nil
            }

            if hit("nav.up") {
                browser.goUp()
                return nil
            }

            if hit("search.deep") {
                browser.promptDeepSearch()
                return nil
            }
            if hit("assistant.toggle") {
                browser.showAssistantPanel.toggle()
                return nil
            }
            if hit("assistant.focus") {
                browser.showAssistantPanel = true
                return nil
            }
            if hit("dual.toggle") {
                browser.toggleDualPane()
                return nil
            }
            if hit("nav.downloads") {
                browser.navigateToDownloads()
                return nil
            }
            if hit("files.favorite") {
                browser.addCurrentFolderToFavorites()
                return nil
            }
            if hit("files.open") {
                browser.openSelection()
                return nil
            }
            if hit("files.trash") {
                browser.moveSelectionToTrash()
                return nil
            }
            if hit("files.newFile") {
                browser.promptNewFile()
                return nil
            }
            if hit("files.newFolder") {
                browser.promptNewFolder()
                return nil
            }
            if hit("files.duplicate") {
                browser.duplicateSelection()
                return nil
            }
            if hit("files.selectAll") {
                browser.selectAllVisible()
                return nil
            }
            // «Modo varios» comparte ⌘⇧M de fábrica con «Mover → Destino»;
            // si dual pane está activo, el movimiento ya se manejó arriba.
            if hit("view.multi") {
                browser.multiSelectMode.toggle()
                return nil
            }

            return event
        }

        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            if handleVoicePTTKeyUp(event, browser: browser) {
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

    private static func handleVoicePTTKeyDown(_ event: NSEvent, browser: BrowserModel) -> Bool {
        guard !event.isARepeat else { return voicePTTHeld }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""
        let overrides = browser.store.preferences.keyboardHotkeyOverrides
        guard let chord = AppHotkeyCatalog.resolvedChord(id: "assistant.voice", overrides: overrides),
              chord.matches(
                keyCode: event.keyCode,
                characters: chars,
                command: flags.contains(.command),
                option: flags.contains(.option),
                shift: flags.contains(.shift),
                control: flags.contains(.control)
              ) else { return false }
        if NSApp.keyWindow?.attachedSheet != nil { return false }
        if browser.showOllamaSetupDialog || browser.showFolderHandlerSetupDialog { return false }
        guard !voicePTTHeld else { return true }
        voicePTTHeld = true
        browser.showAssistantPanel = true
        VoiceCaptureController.shared.beginPushToTalk()
        return true
    }

    private static func handleVoicePTTKeyUp(_ event: NSEvent, browser: BrowserModel) -> Bool {
        guard voicePTTHeld else { return false }
        let overrides = browser.store.preferences.keyboardHotkeyOverrides
        guard let chord = AppHotkeyCatalog.resolvedChord(id: "assistant.voice", overrides: overrides) else { return false }
        // Soltar la tecla principal del acorde (p. ej. Espacio).
        guard event.keyCode == chord.keyCode || (!chord.character.isEmpty && (event.charactersIgnoringModifiers ?? "").lowercased() == chord.character) else {
            return false
        }
        endVoicePTT()
        return true
    }

    private static func handleVoicePTTFlagsChanged(_ event: NSEvent) {
        guard voicePTTHeld else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let browser = browserRef else { return }
        let overrides = browser.store.preferences.keyboardHotkeyOverrides
        guard let chord = AppHotkeyCatalog.resolvedChord(id: "assistant.voice", overrides: overrides) else { return }
        // Si el acorde exige ⌃ y se soltó, terminar.
        if chord.control, !flags.contains(.control) {
            endVoicePTT()
        }
        if chord.option, !flags.contains(.option) {
            endVoicePTT()
        }
        if chord.command, !flags.contains(.command) {
            endVoicePTT()
        }
        if chord.shift, !flags.contains(.shift) {
            endVoicePTT()
        }
    }

    private static func endVoicePTT() {
        guard voicePTTHeld else { return }
        voicePTTHeld = false
        VoiceCaptureController.shared.endPushToTalk()
    }

    /// Return / keypad Enter / Esc mientras hay un sheet de confirmación.
    private static func handleModalDialogKeys(_ event: NSEvent, browser: BrowserModel) -> Bool {
        guard browser.hasModalSheet else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.keyCode
        let bare = !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)

        if key == 53, bare || flags.isEmpty {
            browser.dismissModalSheet()
            return true
        }
        // 36 = Return · 76 = Enter del teclado numérico
        if bare, key == 36 || key == 76 {
            browser.confirmPrimaryModalAction()
            return true
        }
        return false
    }

    private static func shouldIgnore(_ event: NSEvent, browser: BrowserModel) -> Bool {
        if isEditingText { return true }
        if NSApp.keyWindow?.attachedSheet != nil { return true }
        if browser.hasModalSheet { return true }
        return false
    }

    private static var isEditingText: Bool {
        guard let fr = NSApp.keyWindow?.firstResponder else { return false }
        if fr is NSTextView || fr is NSTextField { return true }
        let name = NSStringFromClass(type(of: fr))
        return name.contains("FieldEditor") || name.contains("TextInput")
    }
}

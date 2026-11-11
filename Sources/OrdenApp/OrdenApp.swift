import SwiftUI
import OrdenCore
import AppKit

@main
struct OrdenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Solo para Settings (preferencias); cada ventana de archivos tiene su propio modelo.
    @StateObject private var settingsBrowser = BrowserModel()

    init() {
        #if !DEBUG
        ReleaseIntegrity.hardenAtLaunch()
        #endif

        let storedLang = PreferencesStore.shared.preferences.appLanguage
        L10n.activeLanguage = storedLang
        UserDefaults.standard.set(storedLang.rawValue, forKey: "findaro_app_language")
        if storedLang == .auto {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([storedLang.isEnglish ? "en" : "es"], forKey: "AppleLanguages")
        }

        // T-03: Iniciar comprobación periódica (cada 24h) y comprobación al inicio
        LicenseStore.shared.startPeriodicCheck()
        Task {
            await LicenseStore.shared.checkServerStatus()
            // Prueba anclada en el servidor: borrar el Llavero o reinstalar no reinicia los 14 días.
            await LicenseStore.shared.syncDeviceTrial()
        }
    }

    var body: some Scene {
        WindowGroup(id: "browser") {
            BrowserRootView()
        }
        // Vacío: no crear ventanas nuevas por cada open/URL de Chrome/LS.
        // AppDelegate + OpenFolderBridge reusan la ventana registrada.
        .handlesExternalEvents(matching: [])
        .defaultSize(
            width: OrdenDisplayMetrics.preferredWindowSize().width,
            height: OrdenDisplayMetrics.preferredWindowSize().height
        )
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            FindaroCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settingsBrowser)
        }
    }
}

private struct FindaroCommands: Commands {
    @AppStorage("findaro_app_language") private var appLangStorage: String = "en"
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.findaroBrowser) private var focusedBrowser
    @FocusedValue(\.findaroSession) private var focusedSession

    /// FocusedValue falla a menudo con toolbar/search; el registro de ventana es el respaldo.
    private var browser: BrowserModel? { focusedBrowser ?? FindaroWindowRegistry.keyBrowser }
    private var session: BrowserWindowSession? { focusedSession ?? FindaroWindowRegistry.keySession }

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: appLangStorage) ?? .english
    }

    private func setGlobalLanguage(_ lang: AppLanguage) {
        // Primero el flag de UI (@AppStorage) para que la palomita no parpadee a English
        // mientras PreferencesStore notifica y BrowserModel sincroniza.
        appLangStorage = lang.rawValue
        UserDefaults.standard.set(lang.rawValue, forKey: "findaro_app_language")
        L10n.activeLanguage = lang
        if lang == .auto {
            // Sin override: la app sigue Locale.preferredLanguages.
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([lang.isEnglish ? "en" : "es"], forKey: "AppleLanguages")
        }
        PreferencesStore.shared.update { $0.appLanguage = lang }
        browser?.setAppLanguage(lang)
        AppMenuLocalizer.applyLocalization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AppMenuLocalizer.applyLocalization()
        }
    }

    @ViewBuilder
    private func languageMenuItem(_ lang: AppLanguage, title: String) -> some View {
        Button {
            setGlobalLanguage(lang)
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                if currentLanguage == lang {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.s("Acerca de Findaro", "About Findaro")) {
                AboutOrdena.show()
            }
            Button(L10n.s("Buscar actualizaciones…", "Check for Updates…")) {
                Task { await AppUpdateChecker.shared.check(interactive: true) }
            }
        }

        CommandGroup(after: .appSettings) {
            Menu(L10n.s("Idioma / Language", "Language / Idioma")) {
                languageMenuItem(
                    .auto,
                    title: L10n.s("Automático (Sistema)", "Automatic (System)")
                )
                languageMenuItem(.spanish, title: "Español")
                languageMenuItem(.english, title: "English")
            }

            if DefaultFileViewerManager.isEnabled {
                Button(L10n.s("Restaurar Finder como explorador", "Restore Finder as File Viewer")) {
                    _ = DefaultFileViewerManager.disable()
                }
            }
            Button(L10n.s("Desinstalar Findaro…", "Uninstall Findaro…")) {
                FindaroUninstaller.confirmAndUninstall()
            }
        }

        CommandGroup(replacing: .help) {
            Button(L10n.s("Ayuda de Findaro", "Findaro Help")) {
                FindaroHelpWindow.show()
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            Button(L10n.s("Nueva ventana", "New Window")) {
                openWindow(id: "browser")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            Button(L10n.s("Nueva pestaña", "New Tab")) {
                (session ?? FindaroWindowRegistry.keySession)?.addTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            Button(L10n.s("Cerrar pestaña", "Close Tab")) {
                (session ?? FindaroWindowRegistry.keySession)?.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            Button(L10n.s("Pestaña anterior", "Previous Tab")) {
                (session ?? FindaroWindowRegistry.keySession)?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            Button(L10n.s("Pestaña siguiente", "Next Tab")) {
                (session ?? FindaroWindowRegistry.keySession)?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            Button(L10n.s("Mover pestaña a la izquierda", "Move Tab Left")) {
                if let s = (session ?? FindaroWindowRegistry.keySession) {
                    s.moveTabLeft(s.selectedTabID)
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button(L10n.s("Mover pestaña a la derecha", "Move Tab Right")) {
                if let s = (session ?? FindaroWindowRegistry.keySession) {
                    s.moveTabRight(s.selectedTabID)
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Divider()
            // Atajos ⌘N / ⇧⌘N: solo SelectionCancelMonitor (evitar doble disparo menú+monitor).
            Button(L10n.s("Nuevo archivo", "New File")) { browser?.promptNewFile() }
            Button(L10n.s("Nueva carpeta", "New Folder")) { browser?.promptNewFolder() }
        }

        CommandGroup(after: .pasteboard) {
            Button(L10n.s("Deshacer", "Undo")) { browser?.undoLastFileOp() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(browser?.canUndo ?? false))
            Button(L10n.s("Copiar a bandeja", "Copy to Tray")) { browser?.addSelectionToShelf(intent: .copy) }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(browser == nil)
            Button(L10n.s("Cortar a bandeja", "Cut to Tray")) { browser?.addSelectionToShelf(intent: .move) }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(browser == nil)
            Button(L10n.s("Soltar bandeja aquí", "Paste Tray Here")) { browser?.pasteFromPasteboard() }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(browser == nil)
            Button(L10n.s("Duplicar", "Duplicate")) { browser?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(browser == nil)
            Button(L10n.s("Copiar ruta", "Copy Path")) { browser?.copySelectedPaths() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(browser == nil)
        }

        CommandMenu(L10n.s("Buscar", "Search")) {
            // Atajo ⌘4: solo SelectionCancelMonitor (evita sheet que parpadea / reinicia draft).
            Button(L10n.s("Buscar en subcarpetas…", "Search in Subfolders…")) { browser?.promptDeepSearch() }
                .disabled(browser == nil)
            Button(L10n.s("Orden normal / salir filtros (Esc)", "Normal View / Clear Filters (Esc)")) {
                guard let browser else { return }
                if browser.hasActiveViewFilters {
                    browser.resetToNormalView()
                } else {
                    browser.clearDeepSearch()
                }
            }
            .disabled(!(browser?.hasActiveViewFilters ?? false))
            Button((browser?.dualPaneEnabled ?? false) ? L10n.s("Un panel", "Single Pane") : L10n.s("Dos paneles", "Dual Pane")) {
                browser?.toggleDualPane()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Divider()
            Button(L10n.s("Panel Origen", "Origin Pane")) { browser?.focusOriginPane() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                .disabled(!(browser?.dualPaneEnabled ?? false))
            Button(L10n.s("Panel Destino", "Destination Pane")) { browser?.focusDestinationPane() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                .disabled(!(browser?.dualPaneEnabled ?? false))
            Button(L10n.s("Cambiar de panel (Tab)", "Toggle Focused Pane (Tab)")) { browser?.toggleFocusedPane() }
                .disabled(!(browser?.dualPaneEnabled ?? false))
            Button(L10n.s("Mover selección → Destino", "Move Selection → Destination")) {
                browser?.transferPrimarySelectionToSecondary(copy: false)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!(browser?.dualPaneEnabled ?? false) || (browser?.selectedIDs.isEmpty ?? true))
            Button(L10n.s("Mover selección → Origen", "Move Selection → Origin")) {
                browser?.transferSecondarySelectionToPrimary(copy: false)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift, .option])
            .disabled(!(browser?.dualPaneEnabled ?? false) || (browser?.secondarySelectedIDs.isEmpty ?? true))
            Button(L10n.s("Intercambiar paneles", "Swap Panes")) {
                browser?.swapPaneFolders()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!(browser?.dualPaneEnabled ?? false))
        }

        CommandMenu(L10n.s("Asistente", "Assistant")) {
            // Atajos ⌘5 / ⌘6: solo SelectionCancelMonitor (toggle doble = se prende y apaga).
            Button((browser?.showAssistantPanel ?? false) ? L10n.s("Ocultar asistente", "Hide Assistant") : L10n.s("Mostrar asistente", "Show Assistant")) {
                browser?.showAssistantPanel.toggle()
            }
            .disabled(browser == nil)
            Button(L10n.s("Configurar Ollama…", "Configure Ollama…")) {
                browser?.showAssistantPanel = true
                browser?.showOllamaSetupDialog = true
            }
            .disabled(browser == nil)
            Button(L10n.s("Ir al asistente", "Focus Assistant")) {
                browser?.showAssistantPanel = true
            }
            .disabled(browser == nil)
            Button(L10n.s("Hablar (mantener ⌃Espacio)", "Talk (Hold ⌃Space)")) {
                browser?.showAssistantPanel = true
            }
            .disabled(browser == nil)
        }

        CommandMenu(L10n.s("Ir", "Go")) {
            Button(L10n.s("Atrás", "Back")) { browser?.goBack() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(browser == nil)
            Button(L10n.s("Adelante", "Forward")) { browser?.goForward() }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(browser == nil)
            Button(L10n.s("Atrás (⌥←)", "Back (⌥←)")) { browser?.goBack() }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(browser == nil)
            Button(L10n.s("Adelante (⌥→)", "Forward (⌥→)")) { browser?.goForward() }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(browser == nil)
            Button(L10n.s("Arriba", "Enclosing Folder")) { browser?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(browser == nil)
            // Atajo ⌘3: solo SelectionCancelMonitor (evita sheet que parpadea / reinicia draft).
            Button(L10n.s("Ir a carpeta…", "Go to Folder…")) { browser?.promptGoToFolder() }
                .disabled(browser == nil)
            Button(L10n.s("Editar ruta (omnibox)", "Edit Path (Omnibox)")) { browser?.beginPathOmnibox() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(browser == nil)
            Divider()
            Button(L10n.s("Descargas", "Downloads")) { browser?.navigateToDownloads() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(browser == nil)
            Button((browser?.showHiddenFiles ?? false) ? L10n.s("Ocultar archivos ocultos", "Hide Hidden Files") : L10n.s("Mostrar archivos ocultos", "Show Hidden Files")) {
                browser?.toggleShowHiddenFiles()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Button((browser?.flattenFolderView ?? false) ? L10n.s("Vista de carpeta", "Folder View") : L10n.s("Vista plana", "Flat View")) {
                browser?.toggleFlattenFolderView()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Button(L10n.s("Escritorio", "Desktop")) { browser?.navigateToDesktop() }
                .disabled(browser == nil)
            Button(L10n.s("Documentos", "Documents")) { browser?.navigateToDocuments() }
                .disabled(browser == nil)
            Divider()
            Button(L10n.s("Añadir carpeta actual a Favoritos", "Add Current Folder to Favorites")) {
                browser?.addCurrentFolderToFavorites()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Button(L10n.s("Elegir carpeta para Favoritos…", "Choose Folder for Favorites…")) {
                browser?.pickFolderAsFavorite()
            }
            .disabled(browser == nil)
            Button(L10n.s("Nueva carpeta inteligente…", "New Smart Folder…")) {
                browser?.promptNewSmartFolder()
            }
            .disabled(browser == nil)
            Button(L10n.s("Guardar búsqueda actual como carpeta inteligente…", "Save Current Search as Smart Folder…")) {
                browser?.promptSaveCurrentViewAsSmartFolder()
            }
            .disabled(browser == nil)
        }

        CommandMenu(L10n.s("Archivo+", "File+")) {
            Button(L10n.s("Nueva ventana", "New Window")) { openWindow(id: "browser") }
            Button(L10n.s("Nueva pestaña", "New Tab")) { session?.addTab() }
            Button(L10n.s("Cerrar pestaña", "Close Tab")) { session?.closeActiveTab() }
            Button(L10n.s("Pestaña siguiente", "Next Tab")) { session?.selectNextTab() }
            Button(L10n.s("Pestaña anterior", "Previous Tab")) { session?.selectPreviousTab() }
            Divider()
            Button(L10n.s("Nuevo archivo", "New File")) { browser?.promptNewFile() }
                .disabled(browser == nil)
            Button(L10n.s("Nueva carpeta", "New Folder")) { browser?.promptNewFolder() }
                .disabled(browser == nil)
            Button(L10n.s("Abrir Terminal aquí", "Open Terminal Here")) { browser?.openTerminalHere() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(browser == nil)
            Button(L10n.s("Renombrar", "Rename")) { browser?.promptRename() }
                .keyboardShortcut("r", modifiers: .control)
                .disabled(browser == nil)
            Button(L10n.s("Duplicar", "Duplicate")) { browser?.duplicateSelection() }
                .disabled(browser == nil)
            Divider()
            Button(L10n.s("Seleccionar todos", "Select All")) { browser?.selectAllVisible() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(browser == nil)
            Button(L10n.s("Quitar selección / bandeja", "Deselect / Clear Tray")) {
                browser?.cancelSelectionOrClearTray()
            }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(browser == nil)
            Button(L10n.s("Modo varios", "Multi-Select Mode")) { browser?.multiSelectMode.toggle() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(browser == nil)
            Divider()
            Button(L10n.s("Abrir selección", "Open Selection")) { browser?.openSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(browser == nil)
            Button(L10n.s("Vista rápida", "Quick Look")) { browser?.quickLookSelection() }
                .disabled(browser == nil)
            if browser?.isViewingTrash == true {
                Button(L10n.s("Sacar de la Papelera", "Restore from Trash")) { browser?.restoreSelectionFromTrash() }
                    .disabled(browser == nil)
                Button(L10n.s("Eliminar para siempre", "Delete Permanently")) { browser?.permanentlyDeleteSelection(confirm: true) }
                    .disabled(browser == nil)
            } else {
                // Atajo ⌫ solo vía SelectionCancelMonitor (si va en el menú, roba ⌫ a los campos de texto).
                Button(L10n.s("Mover a la Papelera", "Move to Trash")) { browser?.moveSelectionToTrash() }
                    .disabled(browser == nil)
            }
            Divider()
            Button(L10n.s("Usar Findaro para abrir carpetas…", "Use Findaro to Open Folders…")) {
                browser?.runFolderHandlerSetup()
            }
            .disabled(browser == nil)
            Button(L10n.s("Abrir Descargas (⌃⌥A)", "Open Downloads (⌃⌥A)")) {
                GlobalHotKey.activateOrdena()
            }
            Divider()
            Button(L10n.s("Limpiar caché de miniaturas", "Clear Thumbnail Cache")) {
                ThumbnailStore.shared.clearAll()
                browser?.reload()
                browser?.statusMessage = L10n.s("Caché de miniaturas limpia", "Thumbnail cache cleared")
            }
            .disabled(browser == nil)
            Button(L10n.s("Buscar actualizaciones…", "Check for Updates…")) {
                Task { await AppUpdateChecker.shared.check(interactive: true) }
            }
        }
    }
}

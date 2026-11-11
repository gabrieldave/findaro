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
                .findaroThemed()
        }
    }
}

private struct FindaroCommands: Commands {
    @AppStorage("findaro_app_language") private var appLangStorage: String = "en"
    @Environment(\.openWindow) private var openWindow

    /// NUNCA leer BrowserModel en el `body` de Commands (títulos/disabled dinámicos).
    /// Eso reconstruye el NSMenu mientras está abierto sobre la ventana → parpadeo / tildado.
    /// Resolver el browser solo dentro de las acciones, vía registry.
    @MainActor
    private func browser() -> BrowserModel? { FindaroWindowRegistry.keyBrowser }
    @MainActor
    private func session() -> BrowserWindowSession? { FindaroWindowRegistry.keySession }

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: appLangStorage) ?? .english
    }

    private func setGlobalLanguage(_ lang: AppLanguage) {
        appLangStorage = lang.rawValue
        UserDefaults.standard.set(lang.rawValue, forKey: "findaro_app_language")
        L10n.activeLanguage = lang
        if lang == .auto {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([lang.isEnglish ? "en" : "es"], forKey: "AppleLanguages")
        }
        PreferencesStore.shared.update { $0.appLanguage = lang }
        for session in FindaroWindowRegistry.allSessions {
            session.activeBrowser.setAppLanguage(lang)
        }
        AppMenuLocalizer.requestLocalization()
    }

    private func languageMenuItem(_ lang: AppLanguage, title: String) -> some View {
        let checked = currentLanguage == lang
        return Button((checked ? "✓ " : "    ") + title) {
            setGlobalLanguage(lang)
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
            languageMenuItem(
                .auto,
                title: L10n.s("Idioma: Automático (Sistema)", "Language: Automatic (System)")
            )
            languageMenuItem(.spanish, title: L10n.s("Idioma: Español", "Language: Español"))
            languageMenuItem(.english, title: L10n.s("Idioma: English", "Language: English"))

            if DefaultFileViewerManager.isEnabled {
                Button(L10n.s("Restaurar Finder como explorador", "Restore Finder as File Viewer")) {
                    _ = DefaultFileViewerManager.disable()
                }
            }
            Button(L10n.s("Desinstalar Findaro…", "Uninstall Findaro…")) {
                FindaroUninstaller.confirmAndUninstall()
            }
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button(L10n.s("Iconos", "Icons")) { browser()?.setViewMode(.icons) }
            Button(L10n.s("Lista", "List")) { browser()?.setViewMode(.list) }
            Button(L10n.s("Columnas", "Columns")) { browser()?.setViewMode(.columns) }
            Button(L10n.s("Galería", "Gallery")) { browser()?.setViewMode(.gallery) }
            Divider()
            // Títulos fijos (no leen dualPane/hidden en body → no rebuild al hover).
            Button(L10n.s("Alternar dos paneles", "Toggle Dual Pane")) { browser()?.toggleDualPane() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button(L10n.s("Alternar archivos ocultos", "Toggle Hidden Files")) { browser()?.toggleShowHiddenFiles() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button(L10n.s("Alternar vista plana", "Toggle Flat View")) { browser()?.toggleFlattenFolderView() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button(L10n.s("Orden normal / salir filtros (Esc)", "Normal View / Clear Filters (Esc)")) {
                guard let browser = browser() else { return }
                if browser.hasActiveViewFilters {
                    browser.resetToNormalView()
                } else {
                    browser.clearDeepSearch()
                }
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
                session()?.addTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            Button(L10n.s("Cerrar pestaña", "Close Tab")) {
                session()?.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            Button(L10n.s("Pestaña anterior", "Previous Tab")) {
                session()?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            Button(L10n.s("Pestaña siguiente", "Next Tab")) {
                session()?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            Button(L10n.s("Mover pestaña a la izquierda", "Move Tab Left")) {
                if let s = session() { s.moveTabLeft(s.selectedTabID) }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button(L10n.s("Mover pestaña a la derecha", "Move Tab Right")) {
                if let s = session() { s.moveTabRight(s.selectedTabID) }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Divider()
            Button(L10n.s("Nuevo archivo", "New File")) { browser()?.promptNewFile() }
            Button(L10n.s("Nueva carpeta", "New Folder")) { browser()?.promptNewFolder() }
        }

        // Reemplazar (no «after») para no dejar Cortar/Copiar/Pegar del sistema + Writing Tools
        // encima de la ventana (provoca parpadeo del menú traslúcido).
        CommandGroup(replacing: .undoRedo) {
            Button(L10n.s("Deshacer", "Undo")) { browser()?.undoLastFileOp() }
                .keyboardShortcut("z", modifiers: .command)
        }
        CommandGroup(replacing: .pasteboard) {
            Button(L10n.s("Copiar a bandeja", "Copy to Tray")) { browser()?.addSelectionToShelf(intent: .copy) }
                .keyboardShortcut("c", modifiers: .command)
            Button(L10n.s("Cortar a bandeja", "Cut to Tray")) { browser()?.addSelectionToShelf(intent: .move) }
                .keyboardShortcut("x", modifiers: .command)
            Button(L10n.s("Soltar bandeja aquí", "Paste Tray Here")) { browser()?.pasteFromPasteboard() }
                .keyboardShortcut("v", modifiers: .command)
            Button(L10n.s("Duplicar", "Duplicate")) { browser()?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
            Button(L10n.s("Copiar ruta", "Copy Path")) { browser()?.copySelectedPaths() }
                .keyboardShortcut("c", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .textEditing) {
            Button(L10n.s("Seleccionar todos", "Select All")) { browser()?.selectAllVisible() }
                .keyboardShortcut("a", modifiers: .command)
        }

        CommandMenu(L10n.s("Buscar", "Search")) {
            Button(L10n.s("Buscar en subcarpetas…", "Search in Subfolders…")) { browser()?.promptDeepSearch() }
            Button(L10n.s("Orden normal / salir filtros (Esc)", "Normal View / Clear Filters (Esc)")) {
                guard let browser = browser() else { return }
                if browser.hasActiveViewFilters {
                    browser.resetToNormalView()
                } else {
                    browser.clearDeepSearch()
                }
            }
            Button(L10n.s("Alternar dos paneles", "Toggle Dual Pane")) { browser()?.toggleDualPane() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button(L10n.s("Panel Origen", "Origin Pane")) { browser()?.focusOriginPane() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            Button(L10n.s("Panel Destino", "Destination Pane")) { browser()?.focusDestinationPane() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            Button(L10n.s("Cambiar de panel (Tab)", "Toggle Focused Pane (Tab)")) { browser()?.toggleFocusedPane() }
            Button(L10n.s("Mover selección → Destino", "Move Selection → Destination")) {
                browser()?.transferPrimarySelectionToSecondary(copy: false)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Button(L10n.s("Mover selección → Origen", "Move Selection → Origin")) {
                browser()?.transferSecondarySelectionToPrimary(copy: false)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift, .option])
            Button(L10n.s("Intercambiar paneles", "Swap Panes")) {
                browser()?.swapPaneFolders()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandMenu(L10n.s("Asistente", "Assistant")) {
            Button(L10n.s("Mostrar / ocultar asistente", "Show / Hide Assistant")) {
                browser()?.showAssistantPanel.toggle()
            }
            Button(L10n.s("Configurar Ollama…", "Configure Ollama…")) {
                browser()?.showAssistantPanel = true
                browser()?.showOllamaSetupDialog = true
            }
            Button(L10n.s("Ir al asistente", "Focus Assistant")) {
                browser()?.showAssistantPanel = true
            }
            Button(L10n.s("Hablar (mantener ⌃Espacio)", "Talk (Hold ⌃Space)")) {
                browser()?.showAssistantPanel = true
            }
        }

        CommandMenu(L10n.s("Ir", "Go")) {
            Button(L10n.s("Atrás", "Back")) { browser()?.goBack() }
                .keyboardShortcut("1", modifiers: .command)
            Button(L10n.s("Adelante", "Forward")) { browser()?.goForward() }
                .keyboardShortcut("2", modifiers: .command)
            Button(L10n.s("Atrás (⌥←)", "Back (⌥←)")) { browser()?.goBack() }
                .keyboardShortcut(.leftArrow, modifiers: .option)
            Button(L10n.s("Adelante (⌥→)", "Forward (⌥→)")) { browser()?.goForward() }
                .keyboardShortcut(.rightArrow, modifiers: .option)
            Button(L10n.s("Arriba", "Enclosing Folder")) { browser()?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button(L10n.s("Ir a carpeta…", "Go to Folder…")) { browser()?.promptGoToFolder() }
            Button(L10n.s("Editar ruta (omnibox)", "Edit Path (Omnibox)")) { browser()?.beginPathOmnibox() }
                .keyboardShortcut("e", modifiers: .command)
            Divider()
            Button(L10n.s("Descargas", "Downloads")) { browser()?.navigateToDownloads() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button(L10n.s("Alternar archivos ocultos", "Toggle Hidden Files")) { browser()?.toggleShowHiddenFiles() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button(L10n.s("Alternar vista plana", "Toggle Flat View")) { browser()?.toggleFlattenFolderView() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button(L10n.s("Escritorio", "Desktop")) { browser()?.navigateToDesktop() }
            Button(L10n.s("Documentos", "Documents")) { browser()?.navigateToDocuments() }
            Divider()
            Button(L10n.s("Añadir carpeta actual a Favoritos", "Add Current Folder to Favorites")) {
                browser()?.addCurrentFolderToFavorites()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Button(L10n.s("Elegir carpeta para Favoritos…", "Choose Folder for Favorites…")) {
                browser()?.pickFolderAsFavorite()
            }
            Button(L10n.s("Nueva carpeta inteligente…", "New Smart Folder…")) {
                browser()?.promptNewSmartFolder()
            }
            Button(L10n.s("Guardar búsqueda actual como carpeta inteligente…", "Save Current Search as Smart Folder…")) {
                browser()?.promptSaveCurrentViewAsSmartFolder()
            }
        }

        CommandMenu(L10n.s("Archivo+", "File+")) {
            Button(L10n.s("Nueva ventana", "New Window")) { openWindow(id: "browser") }
            Button(L10n.s("Nueva pestaña", "New Tab")) { session()?.addTab() }
            Button(L10n.s("Cerrar pestaña", "Close Tab")) { session()?.closeActiveTab() }
            Button(L10n.s("Pestaña siguiente", "Next Tab")) { session()?.selectNextTab() }
            Button(L10n.s("Pestaña anterior", "Previous Tab")) { session()?.selectPreviousTab() }
            Divider()
            Button(L10n.s("Nuevo archivo", "New File")) { browser()?.promptNewFile() }
            Button(L10n.s("Nueva carpeta", "New Folder")) { browser()?.promptNewFolder() }
            Button(L10n.s("Abrir Terminal aquí", "Open Terminal Here")) { browser()?.openTerminalHere() }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button(L10n.s("Renombrar", "Rename")) { browser()?.promptRename() }
                .keyboardShortcut("r", modifiers: .control)
            Button(L10n.s("Duplicar", "Duplicate")) { browser()?.duplicateSelection() }
            Divider()
            Button(L10n.s("Seleccionar todos", "Select All")) { browser()?.selectAllVisible() }
                .keyboardShortcut("a", modifiers: .command)
            Button(L10n.s("Quitar selección / bandeja", "Deselect / Clear Tray")) {
                browser()?.cancelSelectionOrClearTray()
            }
            .keyboardShortcut(.escape, modifiers: [])
            Button(L10n.s("Modo varios", "Multi-Select Mode")) { browser()?.multiSelectMode.toggle() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button(L10n.s("Abrir selección", "Open Selection")) { browser()?.openSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button(L10n.s("Vista rápida", "Quick Look")) { browser()?.quickLookSelection() }
            Button(L10n.s("Mover a la Papelera", "Move to Trash")) { browser()?.moveSelectionToTrash() }
            Button(L10n.s("Sacar de la Papelera", "Restore from Trash")) { browser()?.restoreSelectionFromTrash() }
            Button(L10n.s("Eliminar para siempre", "Delete Permanently")) { browser()?.permanentlyDeleteSelection(confirm: true) }
            Divider()
            Button(L10n.s("Usar Findaro para abrir carpetas…", "Use Findaro to Open Folders…")) {
                browser()?.runFolderHandlerSetup()
            }
            Button(L10n.s("Abrir Descargas (⌃⌥A)", "Open Downloads (⌃⌥A)")) {
                GlobalHotKey.activateOrdena()
            }
            Divider()
            Button(L10n.s("Limpiar caché de miniaturas", "Clear Thumbnail Cache")) {
                ThumbnailStore.shared.clearAll()
                browser()?.reload()
                browser()?.statusMessage = L10n.s("Caché de miniaturas limpia", "Thumbnail cache cleared")
            }
            Button(L10n.s("Buscar actualizaciones…", "Check for Updates…")) {
                Task { await AppUpdateChecker.shared.check(interactive: true) }
            }
        }
    }
}

import SwiftUI
import OrdenCore
import AppKit

@main
struct OrdenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Solo para Settings (preferencias); cada ventana de archivos tiene su propio modelo.
    @StateObject private var settingsBrowser = BrowserModel()

    var body: some Scene {
        WindowGroup(id: "browser") {
            BrowserRootView()
        }
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
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.findaroBrowser) private var focusedBrowser
    @FocusedValue(\.findaroSession) private var focusedSession

    /// FocusedValue falla a menudo con toolbar/search; el registro de ventana es el respaldo.
    private var browser: BrowserModel? { focusedBrowser ?? FindaroWindowRegistry.keyBrowser }
    private var session: BrowserWindowSession? { focusedSession ?? FindaroWindowRegistry.keySession }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Acerca de Findaro") {
                AboutOrdena.show()
            }
            Button("Buscar actualizaciones…") {
                Task { await AppUpdateChecker.shared.check(interactive: true) }
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Nueva ventana") {
                openWindow(id: "browser")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Nueva pestaña") {
                (session ?? FindaroWindowRegistry.keySession)?.addTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("Cerrar pestaña") {
                (session ?? FindaroWindowRegistry.keySession)?.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button("Nuevo archivo") { browser?.promptNewFile() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Nueva carpeta") { browser?.promptNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

        CommandGroup(after: .pasteboard) {
            Button("Deshacer movimiento") { browser?.undoLastFileOp() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(browser?.canUndo ?? false))
            Button("Copiar a bandeja") { browser?.addSelectionToShelf(intent: .copy) }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(browser == nil)
            Button("Cortar a bandeja") { browser?.addSelectionToShelf(intent: .move) }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(browser == nil)
            Button("Soltar bandeja aquí") { browser?.pasteFromPasteboard() }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(browser == nil)
            Button("Duplicar") { browser?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(browser == nil)
            Button("Copiar ruta") { browser?.copySelectedPaths() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(browser == nil)
        }

        CommandMenu("Buscar") {
            Button("Buscar en subcarpetas…") { browser?.promptDeepSearch() }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(browser == nil)
            Button("Orden normal / salir filtros (Esc)") {
                guard let browser else { return }
                if browser.hasActiveViewFilters {
                    browser.resetToNormalView()
                } else {
                    browser.clearDeepSearch()
                }
            }
            .disabled(!(browser?.hasActiveViewFilters ?? false))
            Button((browser?.dualPaneEnabled ?? false) ? "Un panel" : "Dos paneles") {
                browser?.toggleDualPane()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Divider()
            Button("Panel Origen") { browser?.focusOriginPane() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                .disabled(!(browser?.dualPaneEnabled ?? false))
            Button("Panel Destino") { browser?.focusDestinationPane() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                .disabled(!(browser?.dualPaneEnabled ?? false))
            Button("Cambiar de panel (Tab)") { browser?.toggleFocusedPane() }
                .disabled(!(browser?.dualPaneEnabled ?? false))
            Button("Mover selección → Destino") {
                browser?.transferPrimarySelectionToSecondary(copy: false)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!(browser?.dualPaneEnabled ?? false) || (browser?.selectedIDs.isEmpty ?? true))
            Button("Mover selección → Origen") {
                browser?.transferSecondarySelectionToPrimary(copy: false)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift, .option])
            .disabled(!(browser?.dualPaneEnabled ?? false) || (browser?.secondarySelectedIDs.isEmpty ?? true))
            Button("Intercambiar paneles") {
                browser?.swapPaneFolders()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!(browser?.dualPaneEnabled ?? false))
        }

        CommandMenu("Asistente") {
            Button((browser?.showAssistantPanel ?? false) ? "Ocultar asistente" : "Mostrar asistente") {
                browser?.showAssistantPanel.toggle()
            }
            .keyboardShortcut("5", modifiers: .command)
            .disabled(browser == nil)
            Button("Configurar Ollama…") {
                browser?.showAssistantPanel = true
                browser?.showOllamaSetupDialog = true
            }
            .disabled(browser == nil)
            Button("Ir al asistente") {
                browser?.showAssistantPanel = true
            }
            .keyboardShortcut("6", modifiers: .command)
            .disabled(browser == nil)
            Button("Hablar (mantener ⌃Espacio)") {
                browser?.showAssistantPanel = true
            }
            .disabled(browser == nil)
        }

        CommandMenu("Ir") {
            Button("Atrás") { browser?.goBack() }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(browser == nil)
            Button("Adelante") { browser?.goForward() }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(browser == nil)
            Button("Atrás (⌥←)") { browser?.goBack() }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(browser == nil)
            Button("Adelante (⌥→)") { browser?.goForward() }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(browser == nil)
            Button("Arriba") { browser?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(browser == nil)
            Button("Ir a carpeta…") { browser?.promptGoToFolder() }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(browser == nil)
            Button("Editar ruta (omnibox)") { browser?.beginPathOmnibox() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(browser == nil)
            Divider()
            Button("Descargas") { browser?.navigateToDownloads() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(browser == nil)
            Button((browser?.showHiddenFiles ?? false) ? "Ocultar archivos ocultos" : "Mostrar archivos ocultos") {
                browser?.toggleShowHiddenFiles()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Button((browser?.flattenFolderView ?? false) ? "Vista de carpeta" : "Vista plana") {
                browser?.toggleFlattenFolderView()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Button("Escritorio") { browser?.navigateToDesktop() }
                .disabled(browser == nil)
            Button("Documentos") { browser?.navigateToDocuments() }
                .disabled(browser == nil)
            Divider()
            Button("Añadir carpeta actual a Favoritos") {
                browser?.addCurrentFolderToFavorites()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(browser == nil)
            Button("Elegir carpeta para Favoritos…") {
                browser?.pickFolderAsFavorite()
            }
            .disabled(browser == nil)
        }

        CommandMenu("Archivo+") {
            Button("Nueva ventana") { openWindow(id: "browser") }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Nueva pestaña") { session?.addTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Cerrar pestaña") { session?.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Pestaña siguiente") { session?.selectNextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Pestaña anterior") { session?.selectPreviousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            Button("Nuevo archivo") { browser?.promptNewFile() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(browser == nil)
            Button("Nueva carpeta") { browser?.promptNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(browser == nil)
            Button("Abrir Terminal aquí") { browser?.openTerminalHere() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(browser == nil)
            Button("Renombrar") { browser?.promptRename() }
                .disabled(browser == nil)
            Button("Duplicar") { browser?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(browser == nil)
            Divider()
            Button("Seleccionar todos") { browser?.selectAllVisible() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(browser == nil)
            Button("Quitar selección") { browser?.cancelSelection() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(browser == nil)
            Button("Modo varios") { browser?.multiSelectMode.toggle() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(browser == nil)
            Divider()
            Button("Abrir selección") { browser?.openSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(browser == nil)
            Button("Vista rápida") { browser?.quickLookSelection() }
                .disabled(browser == nil)
            Button("Mover a la Papelera") { browser?.moveSelectionToTrash() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(browser == nil)
            Divider()
            Button("Usar Findaro para abrir carpetas…") {
                browser?.runFolderHandlerSetup()
            }
            .disabled(browser == nil)
            Button("Abrir Descargas (⌃⌥O)") {
                GlobalHotKey.activateOrdena()
            }
            Divider()
            Button("Limpiar caché de miniaturas") {
                ThumbnailStore.shared.clearAll()
                browser?.reload()
                browser?.statusMessage = "Caché de miniaturas limpia"
            }
            .disabled(browser == nil)
            Button("Buscar actualizaciones…") {
                Task { await AppUpdateChecker.shared.check(interactive: true) }
            }
        }
    }
}

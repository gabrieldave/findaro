import SwiftUI
import OrdenCore
import AppKit

@main
struct OrdenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var browser = BrowserModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browser)
                // Mínimos reales los fija OrdenDisplayMetrics según la pantalla
                .frame(
                    minWidth: OrdenDisplayMetrics.resolve(windowSize: .zero).windowMinWidth,
                    minHeight: OrdenDisplayMetrics.resolve(windowSize: .zero).windowMinHeight
                )
                .tint(OrdenTheme.accent)
                .onAppear {
                    OrdenWindowFit.applyToOpenWindows()
                    if let pending = OpenFolderBridge.pendingFolderPath {
                        OpenFolderBridge.pendingFolderPath = nil
                        browser.navigate(to: pending, recordHistory: false)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ordenaOpenFolder)) { note in
                    if let path = note.object as? String {
                        browser.navigate(to: path, recordHistory: true)
                    }
                }
                .onOpenURL { url in
                    OpenFolderBridge.ingest(urls: [url])
                }
        }
        .defaultSize(
            width: OrdenDisplayMetrics.preferredWindowSize().width,
            height: OrdenDisplayMetrics.preferredWindowSize().height
        )
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Acerca de Findaro") {
                    AboutOrdena.show()
                }
                Button("Buscar actualizaciones…") {
                    Task { await AppUpdateChecker.shared.check(interactive: true) }
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("Nuevo archivo") { browser.promptNewFile() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Nueva carpeta") { browser.promptNewFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .pasteboard) {
                Button("Deshacer movimiento") { browser.undoLastFileOp() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!browser.canUndo)
                Button("Copiar a bandeja") { browser.addSelectionToShelf(intent: .copy) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Cortar a bandeja") { browser.addSelectionToShelf(intent: .move) }
                    .keyboardShortcut("x", modifiers: .command)
                Button("Soltar bandeja aquí") { browser.pasteFromPasteboard() }
                    .keyboardShortcut("v", modifiers: .command)
                Button("Duplicar") { browser.duplicateSelection() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Copiar ruta") { browser.copySelectedPaths() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
            }

            CommandMenu("Buscar") {
                Button("Buscar en subcarpetas…") { browser.promptDeepSearch() }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Orden normal / salir filtros (Esc)") {
                    if browser.hasActiveViewFilters {
                        browser.resetToNormalView()
                    } else {
                        browser.clearDeepSearch()
                    }
                }
                .disabled(!browser.hasActiveViewFilters)
                Button(browser.dualPaneEnabled ? "Un panel" : "Dos paneles") {
                    browser.toggleDualPane()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Panel Origen") { browser.focusOriginPane() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                    .disabled(!browser.dualPaneEnabled)
                Button("Panel Destino") { browser.focusDestinationPane() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                    .disabled(!browser.dualPaneEnabled)
                Button("Cambiar de panel (Tab)") { browser.toggleFocusedPane() }
                    .disabled(!browser.dualPaneEnabled)
                Button("Mover selección → Destino") {
                    browser.transferPrimarySelectionToSecondary(copy: false)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!browser.dualPaneEnabled || browser.selectedIDs.isEmpty)
                Button("Mover selección → Origen") {
                    browser.transferSecondarySelectionToPrimary(copy: false)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift, .option])
                .disabled(!browser.dualPaneEnabled || browser.secondarySelectedIDs.isEmpty)
            }

            CommandMenu("Asistente") {
                Button(browser.showAssistantPanel ? "Ocultar asistente" : "Mostrar asistente") {
                    browser.showAssistantPanel.toggle()
                }
                .keyboardShortcut("5", modifiers: .command)
                Button("Configurar Ollama…") {
                    browser.showAssistantPanel = true
                    browser.showOllamaSetupDialog = true
                }
                Button("Ir al asistente") {
                    browser.showAssistantPanel = true
                }
                .keyboardShortcut("6", modifiers: .command)
                // Hold real: SelectionCancelMonitor (⌃Espacio keyDown/keyUp).
                Button("Hablar (mantener ⌃Espacio)") {
                    browser.showAssistantPanel = true
                }
            }

            CommandMenu("Ir") {
                // Atajos reales también en SelectionCancelMonitor (NSEvent).
                Button("Atrás") { browser.goBack() }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Adelante") { browser.goForward() }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Atrás (⌥←)") { browser.goBack() }
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                Button("Adelante (⌥→)") { browser.goForward() }
                    .keyboardShortcut(.rightArrow, modifiers: .option)
                Button("Arriba") { browser.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Ir a carpeta…") { browser.promptGoToFolder() }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Editar ruta (omnibox)") { browser.beginPathOmnibox() }
                    .keyboardShortcut("l", modifiers: .command)
                Divider()
                Button("Descargas") { browser.navigateToDownloads() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button(browser.showHiddenFiles ? "Ocultar archivos ocultos" : "Mostrar archivos ocultos") {
                    browser.toggleShowHiddenFiles()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                Button(browser.flattenFolderView ? "Vista de carpeta" : "Vista plana") {
                    browser.toggleFlattenFolderView()
                }
                Button("Escritorio") { browser.navigateToDesktop() }
                Button("Documentos") { browser.navigateToDocuments() }
                Divider()
                Button("Añadir carpeta actual a Favoritos") {
                    browser.addCurrentFolderToFavorites()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Elegir carpeta para Favoritos…") {
                    browser.pickFolderAsFavorite()
                }
            }

            CommandMenu("Archivo+") {
                Button("Nuevo archivo") { browser.promptNewFile() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Nueva carpeta") { browser.promptNewFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Renombrar") { browser.promptRename() }
                Button("Duplicar") { browser.duplicateSelection() }
                    .keyboardShortcut("d", modifiers: .command)
                Divider()
                Button("Seleccionar todos") { browser.selectAllVisible() }
                    .keyboardShortcut("a", modifiers: .command)
                Button("Quitar selección") { browser.cancelSelection() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Modo varios") { browser.multiSelectMode.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button("Abrir selección") { browser.openSelection() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Button("Vista rápida") { browser.quickLookSelection() }
                Button("Mover a la Papelera") { browser.moveSelectionToTrash() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Divider()
                Button("Usar Findaro para abrir carpetas…") {
                    browser.runFolderHandlerSetup()
                }
                Button("Abrir Descargas (⌃⌥O)") {
                    GlobalHotKey.activateOrdena()
                }
                Divider()
                Button("Limpiar caché de miniaturas") {
                    ThumbnailStore.shared.clearAll()
                    browser.reload()
                    browser.statusMessage = "Caché de miniaturas limpia"
                }
                Button("Buscar actualizaciones…") {
                    Task { await AppUpdateChecker.shared.check(interactive: true) }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(browser)
        }
    }
}

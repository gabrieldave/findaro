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
                .frame(minWidth: 1000, minHeight: 640)
                .tint(OrdenTheme.accent)
        }
        .defaultSize(width: 1180, height: 740)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nueva carpeta") { browser.promptNewFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .pasteboard) {
                Button("Copiar archivos") { browser.copySelectionToPasteboard() }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Pegar archivos") { browser.pasteFromPasteboard() }
                    .keyboardShortcut("v", modifiers: .command)
                Button("Duplicar") { browser.duplicateSelection() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Copiar ruta") { browser.copySelectedPaths() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
            }

            CommandMenu("Ir") {
                Button("Descargas") { browser.navigateToDownloads() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Escritorio") { browser.navigateToDesktop() }
                Button("Documentos") { browser.navigateToDocuments() }
                Button("Arriba") { browser.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
            }

            CommandMenu("Archivo+") {
                Button("Nueva carpeta") { browser.promptNewFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Renombrar") { browser.promptRename() }
                    .keyboardShortcut(.return, modifiers: [])
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
            }
        }

        Settings {
            SettingsView()
                .environmentObject(browser)
        }
    }
}

import SwiftUI
import OrdenCore

@main
struct OrdenApp: App {
    @StateObject private var browser = BrowserModel()

    var body: some Scene {
        WindowGroup("Orden") {
            ContentView()
                .environmentObject(browser)
                .frame(minWidth: 880, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .pasteboard) {
                Button("Copiar ruta") {
                    browser.copySelectedPaths()
                }
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

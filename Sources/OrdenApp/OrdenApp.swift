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
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 700)
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

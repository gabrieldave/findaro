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
            CommandMenu("Ir") {
                Button("Descargas") { browser.navigateToDownloads() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Escritorio") { browser.navigateToDesktop() }
                Button("Documentos") { browser.navigateToDocuments() }
                Button("Arriba") { browser.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(browser)
        }
    }
}

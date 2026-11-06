import AppKit

/// Sin esto, un binario SPM corre “en background” y no ves ventana ni Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Traer todas las ventanas al Space actual
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
        GlobalHotKey.install()
        // Paso «usar Ordena para carpetas»: se registra solo, sin buscar menús.
        _ = OpenFolderBridge.setAsDefaultFolderHandler()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKey.uninstall()
    }

    /// Dock / `open -a Ordena ~/Downloads` / doble clic en carpeta (si somos el handler).
    func application(_ application: NSApplication, open urls: [URL]) {
        OpenFolderBridge.ingest(urls: urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        OpenFolderBridge.ingest(urls: [URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        OpenFolderBridge.ingest(urls: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

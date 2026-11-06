import AppKit

/// Sin esto, un binario SPM corre “en background” y no ves ventana ni Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
        CloseToHide.install()
        GlobalHotKey.install()
        _ = OpenFolderBridge.setAsDefaultFolderHandler()
        ThumbnailStore.clearIfAppUpdated()
        // Buscar updates en GitHub tras un momento (no bloquea el arranque).
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            AppUpdateChecker.shared.checkOnLaunchIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKey.uninstall()
    }

    /// Clic en el icono del Dock con la ventana oculta → la vuelve a mostrar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Self.showMainWindows()
        }
        return true
    }

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

    /// ✕ solo oculta; la app sigue en segundo plano (⌘Q para salir de verdad).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    static func showMainWindows() {
        NSApp.activate(ignoringOtherApps: true)
        let titled = NSApp.windows.filter { $0.styleMask.contains(.titled) }
        if titled.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ordena.app"))
            return
        }
        for window in titled {
            window.makeKeyAndOrderFront(nil)
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
    }
}

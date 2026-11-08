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
        // Encajar en la pantalla real (Mac chica / menor resolución).
        DispatchQueue.main.async {
            OrdenWindowFit.applyToOpenWindows()
        }
        CloseToHide.install()
        GlobalHotKey.install()
        _ = OpenFolderBridge.setAsDefaultFolderHandler()
        ThumbnailStore.clearIfAppUpdated()
        // Buscar updates en GitHub tras un momento (no bloquea el arranque).
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            AppUpdateChecker.shared.checkOnLaunchIfNeeded()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                OrdenWindowFit.applyToOpenWindows()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKey.uninstall()
        // Si pospuso una actualización y el DMG ya está listo, instala al salir.
        AppUpdateChecker.shared.installPendingOnTerminateIfNeeded()
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
        // Solo ventanas del explorador — no Ajustes (si no, el atajo global
        // también trae al frente la pestaña General).
        let browserWindows = NSApp.windows.filter { window in
            guard window.styleMask.contains(.titled) else { return false }
            return !isSettingsWindow(window)
        }
        if browserWindows.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Findaro.app"))
            return
        }
        for window in browserWindows {
            window.makeKeyAndOrderFront(nil)
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
    }

    /// Ventana de Preferencias / Ajustes de SwiftUI (no el explorador).
    @MainActor
    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let title = window.title.lowercased()
        if title.contains("ajustes")
            || title.contains("settings")
            || title.contains("preferences")
            || title.contains("preferencias") {
            return true
        }
        if let raw = window.identifier?.rawValue.lowercased(),
           raw.contains("settings") || raw.contains("preference") {
            return true
        }
        // Settings de Findaro: tamaño fijo ~560×520 del TabView.
        let s = window.frame.size
        if abs(s.width - 560) < 8, abs(s.height - 520) < 40 {
            return true
        }
        return false
    }
}

import AppKit
import OrdenCore

/// Sin esto, un binario SPM corre “en background” y no ves ventana ni Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        DefaultFileViewerManager.shared.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Un solo monitor local de teclado (no en onAppear SwiftUI → remount multi-monitor).
        SelectionCancelMonitor.installAtAppLevel()
        // No traer al frente ventanas fantasma: solo exploradores registrados / candidatas.
        DispatchQueue.main.async {
            FindaroWindowRegistry.dismissUnregisteredLookalikes(keeping: nil)
            Self.showMainWindows()
            OrdenWindowFit.applyToOpenWindows()
        }
        CloseToHide.install()
        GlobalHotKey.install()
        _ = OpenFolderBridge.setAsDefaultFolderHandler()
        ThumbnailStore.clearIfAppUpdated()

        // Menubar localization + quitar Writing Tools / Autorrelleno / Dictado del Edit.
        AppMenuLocalizer.applyLocalization()
        EditMenuCleaner.install()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            AppMenuLocalizer.applyLocalization()
            EditMenuCleaner.strip(from: NSApp.mainMenu)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            AppMenuLocalizer.applyLocalization()
            EditMenuCleaner.strip(from: NSApp.mainMenu)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppMenuLocalizer.applyLocalization()
                EditMenuCleaner.strip(from: NSApp.mainMenu)
                // StackDock (y el Dock) a veces solo hacen activate/unhide sin reopen:
                // si no hay explorador visible, restaurar la ventana real.
                if !FindaroWindowRegistry.hasVisibleBrowserWindow() {
                    Self.showMainWindows()
                } else {
                    FindaroWindowRegistry.dismissUnregisteredLookalikes(keeping: nil)
                }
            }
        }
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
                // Solo re-anclar si quedó fuera de TODOS los monitores (no mid-drag).
                // No cerrar preview aquí: Night Shift / scale flicker mataba el overlay
                // y el siguiente Espacio parecía “surtido”. El reset va en didChangeScreen.
                for window in FindaroWindowRegistry.registeredWindows {
                    FindaroScreenPlacement.ensureOnScreen(window)
                }
                OrdenWindowFit.applyToOpenWindows()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SelectionCancelMonitor.uninstall()
        GlobalHotKey.uninstall()
        // Si pospuso una actualización y el DMG ya está listo, instala al salir.
        AppUpdateChecker.shared.installPendingOnTerminateIfNeeded()
    }

    /// Clic en Dock / StackDock: restaurar aunque macOS diga que hay ventanas
    /// (p. ej. un fantasma transparente cuenta como “visible”).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || !FindaroWindowRegistry.hasVisibleBrowserWindow() {
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
        if FindaroWindowRegistry.restoreBrowserWindowsOrRequestNew() {
            return
        }
        // Aún no hay sesión registrada (arranque temprano): front de candidatas reales.
        let fallback = NSApp.windows.filter { window in
            guard window.styleMask.contains(.titled) else { return false }
            return !FindaroWindowRegistry.isSettingsWindow(window)
        }
        if let target = fallback.first(where: { $0.identifier == FindaroWindowRegistry.browserWindowIdentifier })
            ?? fallback.first {
            FindaroWindowRegistry.frontBrowserWindow(target)
        }
    }
}

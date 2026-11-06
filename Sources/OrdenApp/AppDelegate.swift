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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

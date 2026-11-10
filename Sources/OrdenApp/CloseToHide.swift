import AppKit

/// El botón rojo (✕) oculta la ventana; la app sigue viva en el Dock (atajo ⌃⌥A).
@MainActor
enum CloseToHide {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                CloseToHide.configure(window)
            }
        }
        for window in NSApp.windows {
            configure(window)
        }
    }

    private static func configure(_ window: NSWindow) {
        guard window.styleMask.contains(.titled) else { return }
        window.isReleasedWhenClosed = false
        guard let button = window.standardWindowButton(.closeButton) else { return }
        button.target = WindowCloseProxy.shared
        button.action = #selector(WindowCloseProxy.hideWindow(_:))
    }
}

@MainActor
final class WindowCloseProxy: NSObject {
    static let shared = WindowCloseProxy()

    @objc func hideWindow(_ sender: Any?) {
        let window = (sender as? NSView)?.window ?? NSApp.keyWindow
        window?.orderOut(nil)
    }
}

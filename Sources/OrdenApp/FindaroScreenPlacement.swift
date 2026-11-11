import AppKit

/// Colocación fiable en 1…N monitores.
/// `NSWindow.center()` y `NSScreen.main` fallan cuando la app está en un display
/// secundario (p. ej. LG + TYPEC): ventanas/alertas nacen off-screen.
@MainActor
enum FindaroScreenPlacement {
    /// Pantalla donde está el explorador activo, el ratón, o la principal.
    static func preferredScreen() -> NSScreen? {
        if let w = FindaroWindowRegistry.registeredWindows.first(where: \.isKeyWindow)
            ?? FindaroWindowRegistry.registeredWindows.first(where: { $0.isVisible && !$0.isMiniaturized }),
           let s = w.screen {
            return s
        }
        if let key = NSApp.keyWindow?.screen { return key }
        if let underMouse = screenUnderMouse() { return underMouse }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    /// Centra `window` en el visibleFrame de la pantalla preferida (no en (0,0) del layout global).
    static func centerOnPreferredScreen(_ window: NSWindow, size: NSSize? = nil) {
        center(window, on: preferredScreen(), size: size)
    }

    static func center(_ window: NSWindow, on screen: NSScreen?, size: NSSize? = nil) {
        guard let screen = screen ?? preferredScreen() ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        var frame = window.frame
        if let size {
            frame.size = size
        }
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        frame = clamp(frame, to: visible)
        window.setFrame(frame, display: true)
    }

    static func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var f = frame
        if f.width > visible.width { f.size.width = visible.width }
        if f.height > visible.height { f.size.height = visible.height }
        f.origin.x = min(max(f.origin.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - f.width - 8))
        f.origin.y = min(max(f.origin.y, visible.minY + 8), max(visible.minY + 8, visible.maxY - f.height - 8))
        return f
    }

    /// True si algún display tiene intersección con el frame (no solo `isVisible`).
    static func intersectsAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    static func isWindowOnScreen(_ window: NSWindow) -> Bool {
        guard window.isVisible else { return false }
        if window.occlusionState.contains(.visible), intersectsAnyScreen(window.frame) {
            return true
        }
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return intersectsAnyScreen(window.frame)
        }
        let wid = window.windowNumber
        return info.contains { ($0[kCGWindowNumber as String] as? Int) == wid }
    }

    /// Si la ventana quedó fuera de todo visibleFrame (monitor desconectado), re-centra.
    /// No exige `window.screen != nil`: al arrastrar entre monitores `screen` es nil
    /// un instante y recentrar ahí “rompe” layout/preview hasta reiniciar la app.
    static func ensureOnScreen(_ window: NSWindow) {
        if intersectsAnyScreen(window.frame) { return }
        centerOnPreferredScreen(window)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
    }

    /// Factor de escala del display del explorador (thumbnails nítidos en Retina externo).
    static func preferredBackingScaleFactor() -> CGFloat {
        preferredScreen()?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
    }
}

/// Alertas ancladas a la ventana Findaro (o centradas en su pantalla).
@MainActor
enum FindaroAlert {
    @discardableResult
    static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        // Fuerza creación del NSWindow interno para poder posicionarlo.
        FindaroScreenPlacement.centerOnPreferredScreen(alert.window)
        return alert.runModal()
    }
}

import AppKit
import Foundation

/// Enlace fiable ventana ↔ sesión (los menús SwiftUI a veces no reciben FocusedValue).
@MainActor
enum FindaroWindowRegistry {
    private static var sessionsByWindow: [ObjectIdentifier: BrowserWindowSession] = [:]
    private static var windowsBySession: [ObjectIdentifier: NSWindow] = [:]
    private static var lastNewWindowRequestAt: Date?

    static let browserWindowIdentifier = NSUserInterfaceItemIdentifier("findaro.browser")

    static func register(_ session: BrowserWindowSession, for window: NSWindow?) {
        guard let window else { return }
        sessionsByWindow[ObjectIdentifier(window)] = session
        windowsBySession[ObjectIdentifier(session)] = window
        window.identifier = browserWindowIdentifier
        // Cualquier “fantasma” sin sesión no debe tapar el explorador real.
        dismissUnregisteredLookalikes(keeping: window)
    }

    static func unregister(for window: NSWindow?) {
        guard let window else { return }
        let wid = ObjectIdentifier(window)
        if let session = sessionsByWindow.removeValue(forKey: wid) {
            windowsBySession.removeValue(forKey: ObjectIdentifier(session))
        }
    }

    static var keySession: BrowserWindowSession? {
        if let key = NSApp.keyWindow,
           let session = sessionsByWindow[ObjectIdentifier(key)] {
            return session
        }
        if let main = NSApp.mainWindow,
           let session = sessionsByWindow[ObjectIdentifier(main)] {
            return session
        }
        // Preferir una ventana visible ya registrada.
        for window in NSApp.windows where window.isVisible {
            if let session = sessionsByWindow[ObjectIdentifier(window)] {
                return session
            }
        }
        return sessionsByWindow.values.first
    }

    static var keyBrowser: BrowserModel? {
        keySession?.activeBrowser
    }

    static var registeredWindows: [NSWindow] {
        Array(windowsBySession.values)
    }

    static func window(for session: BrowserWindowSession) -> NSWindow? {
        windowsBySession[ObjectIdentifier(session)]
    }

    /// Solo una sesión debe reaccionar a open/reveal; el resto ignora.
    static func claimDelivery(for session: BrowserWindowSession) -> Bool {
        guard let preferred = keySession else { return true }
        guard preferred === session else { return false }
        if let window = window(for: session) {
            frontBrowserWindow(window)
        }
        return true
    }

    /// Evita que N ventanas abiertas disparen N `openWindow` ante la misma notificación.
    static func claimNewWindowRequest() -> Bool {
        let now = Date()
        if let last = lastNewWindowRequestAt, now.timeIntervalSince(last) < 0.6 {
            return false
        }
        lastNewWindowRequestAt = now
        return true
    }

    static func frontBrowserWindow(_ window: NSWindow) {
        dismissUnregisteredLookalikes(keeping: window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    /// Restaura exploradores registrados; si no hay, pide una ventana nueva.
    @discardableResult
    static func restoreBrowserWindowsOrRequestNew() -> Bool {
        dismissUnregisteredLookalikes(keeping: nil)
        let windows = registeredWindows
        if let target = windows.first(where: \.isVisible)
            ?? windows.first(where: { $0 == NSApp.keyWindow })
            ?? windows.first {
            frontBrowserWindow(target)
            return true
        }
        // Arranque: el WindowGroup ya creó la escena pero aún no hizo register.
        let bootstraps = NSApp.windows.filter { window in
            guard window.styleMask.contains(.titled) else { return false }
            return !isSettingsWindow(window)
        }
        if let target = bootstraps.first(where: { $0.identifier == browserWindowIdentifier })
            ?? bootstraps.first {
            frontBrowserWindow(target)
            return true
        }
        NotificationCenter.default.post(name: .findaroOpenNewBrowserWindow, object: nil)
        return false
    }

    static func hasVisibleBrowserWindow() -> Bool {
        registeredWindows.contains { $0.isVisible && !$0.isMiniaturized }
    }

    /// Ventanas tituladas sin sesión (SwiftUI fantasma / escena vieja).
    /// Solo actúa cuando ya hay al menos un explorador registrado, para no
    /// ocultar la ventana real en el arranque antes de `register`.
    static func dismissUnregisteredLookalikes(keeping keep: NSWindow?) {
        guard !sessionsByWindow.isEmpty else { return }
        for window in NSApp.windows {
            if let keep, window === keep { continue }
            guard window.styleMask.contains(.titled) else { continue }
            if isSettingsWindow(window) { continue }
            if isTransientDialogWindow(window) { continue }
            if sessionsByWindow[ObjectIdentifier(window)] != nil { continue }
            if window.identifier == browserWindowIdentifier { continue }
            window.orderOut(nil)
        }
    }

    /// Sheets / paneles SwiftUI a veces aparecen como NSWindow titulada sin sesión.
    /// No son fantasmas del explorador: ocultarlos cierra «Nueva carpeta», ⌘3, ⌘4…
    private static func isTransientDialogWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel { return true }
        if window.isSheet { return true }
        if window.attachedSheet != nil { return true }
        for parent in registeredWindows {
            if window.sheetParent === parent { return true }
            if parent.attachedSheet === window { return true }
        }
        // Diálogos OrdenDialog (~440pt) y similares: nunca orderOut.
        let w = window.frame.size.width
        let h = window.frame.size.height
        if w > 280, w < 720, h > 160, h < 780 { return true }
        return false
    }

    static func isSettingsWindow(_ window: NSWindow) -> Bool {
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
        let s = window.frame.size
        if abs(s.width - 560) < 8, abs(s.height - 520) < 40 {
            return true
        }
        return false
    }
}

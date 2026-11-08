import AppKit
import Foundation

/// Enlace fiable ventana ↔ sesión (los menús SwiftUI a veces no reciben FocusedValue).
@MainActor
enum FindaroWindowRegistry {
    private static var sessionsByWindow: [ObjectIdentifier: BrowserWindowSession] = [:]

    static func register(_ session: BrowserWindowSession, for window: NSWindow?) {
        guard let window else { return }
        sessionsByWindow[ObjectIdentifier(window)] = session
    }

    static func unregister(for window: NSWindow?) {
        guard let window else { return }
        sessionsByWindow.removeValue(forKey: ObjectIdentifier(window))
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
        return sessionsByWindow.values.first
    }

    static var keyBrowser: BrowserModel? {
        keySession?.activeBrowser
    }
}

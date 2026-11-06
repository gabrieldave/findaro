import AppKit
import CoreServices
import Foundation

extension Notification.Name {
    static let ordenaOpenFolder = Notification.Name("ordenaOpenFolder")
}

/// Puente AppKit ↔ SwiftUI para abrir rutas que llegan desde el Dock / Finder / `open`.
@MainActor
enum OpenFolderBridge {
    static let bundleID = "app.ordena.files"

    /// Última carpeta pedida antes de que exista el BrowserModel.
    static var pendingFolderPath: String?

    static func ingest(urls: [URL]) {
        guard let first = urls.first else { return }
        var isDir: ObjCBool = false
        let path: String
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir), isDir.boolValue {
            path = (first.path as NSString).standardizingPath
        } else {
            path = (first.deletingLastPathComponent().path as NSString).standardizingPath
        }
        pendingFolderPath = path
        NotificationCenter.default.post(name: .ordenaOpenFolder, object: path)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Intenta que macOS abra carpetas con Ordena (no quita Finder del sistema).
    @discardableResult
    static func setAsDefaultFolderHandler() -> Bool {
        let id = bundleID as CFString
        var ok = true
        for type in ["public.folder", "public.directory"] as [CFString] {
            let status = LSSetDefaultRoleHandlerForContentType(type, .all, id)
            if status != noErr { ok = false }
        }
        let appURL = URL(fileURLWithPath: "/Applications/Ordena.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            LSRegisterURL(appURL as CFURL, true)
        }
        return ok
    }

    static func isDefaultFolderHandler() -> Bool {
        guard let handler = LSCopyDefaultRoleHandlerForContentType(
            "public.folder" as CFString,
            .all
        )?.takeRetainedValue() as String? else {
            return false
        }
        return handler == bundleID
    }
}

import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

extension Notification.Name {
    static let ordenaOpenFolder = Notification.Name("ordenaOpenFolder")
    static let findaroOpenNewBrowserWindow = Notification.Name("findaroOpenNewBrowserWindow")
}

enum FolderHandlerSetupResult: Equatable {
    /// Ya eres el default (raro en macOS reciente).
    case alreadyDefault
    /// App registrada: el usuario debe elegir «Abrir con → Siempre».
    case readyForOpenWith(appPath: String)
    case appMissing
}

/// Puente AppKit ↔ SwiftUI para abrir rutas que llegan desde el Dock / Finder / `open`.
@MainActor
enum OpenFolderBridge {
    static let bundleID = "app.findaro.files"

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

    /// URL real del .app (no asume solo /Applications).
    static func installedAppURL() -> URL? {
        let candidates = [
            Bundle.main.bundleURL,
            URL(fileURLWithPath: "/Applications/Findaro.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Findaro.app"),
            // Compat: instalación previa durante la migración de marca.
            URL(fileURLWithPath: "/Applications/Ordena.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Ordena.app")
        ]
        for url in candidates {
            let path = url.path
            if path.hasSuffix(".app"), FileManager.default.fileExists(atPath: path) {
                return url
            }
        }
        return nil
    }

    /// Registra Ordena en Launch Services. macOS **no** deja quitar Finder como default
    /// de `public.folder` por API (devuelve -50). Lo útil es aparecer en «Abrir con».
    @discardableResult
    static func prepareFolderOpener() -> FolderHandlerSetupResult {
        guard let appURL = installedAppURL() else { return .appMissing }

        LSRegisterURL(appURL as CFURL, true)

        // Intento moderno (suele fallar igual en carpetas; no es error de Ordena).
        if #available(macOS 12.0, *) {
            let workspace = NSWorkspace.shared
            for type in [UTType.folder, UTType.directory] {
                workspace.setDefaultApplication(at: appURL, toOpen: type) { _ in }
            }
        }

        // API vieja: en Sequoia/Tahoe suele devolver -50 (paramErr) para public.folder.
        let id = bundleID as CFString
        for type in ["public.folder", "public.directory"] as [CFString] {
            _ = LSSetDefaultRoleHandlerForContentType(type, .all, id)
        }

        if isDefaultFolderHandler() {
            return .alreadyDefault
        }
        return .readyForOpenWith(appPath: appURL.path)
    }

    /// Compat con llamadas viejas: true solo si quedó como default o al menos se registró el .app.
    @discardableResult
    static func setAsDefaultFolderHandler() -> Bool {
        switch prepareFolderOpener() {
        case .alreadyDefault, .readyForOpenWith:
            return true
        case .appMissing:
            return false
        }
    }

    static func isDefaultFolderHandler() -> Bool {
        guard let handler = LSCopyDefaultRoleHandlerForContentType(
            "public.folder" as CFString,
            .viewer
        )?.takeRetainedValue() as String? else {
            return false
        }
        return handler == bundleID
    }

}

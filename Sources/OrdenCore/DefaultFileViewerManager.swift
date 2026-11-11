import AppKit
import CoreServices
import Foundation

extension Notification.Name {
    public static let findaroRevealPaths = Notification.Name("findaroRevealPaths")
}

@MainActor
public final class DefaultFileViewerManager: NSObject, ObservableObject {
    public static let shared = DefaultFileViewerManager()

    nonisolated public static let bundleID = "app.findaro.files"
    nonisolated public static let previousViewerKey = "findaro.previous.file_viewer"

    @Published public private(set) var isDefaultViewer: Bool = false

    /// Rutas pendientes recibidas antes de que la ventana del explorador esté lista
    public static var pendingRevealPaths: [String] = []

    private override init() {
        super.init()
        self.isDefaultViewer = Self.isEnabled
    }

    public static var isEnabled: Bool {
        guard let current = CFPreferencesCopyAppValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication) as? String else {
            return false
        }
        return current == bundleID
    }

    public func refreshStatus() {
        self.isDefaultViewer = Self.isEnabled
    }

    @discardableResult
    public static func enable() -> Bool {
        // 1. Guardar el valor anterior de NSFileViewer (puede ser PathFinder, ForkLift u otra)
        if let existing = CFPreferencesCopyAppValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication) as? String {
            if existing != bundleID {
                UserDefaults.standard.set(existing, forKey: previousViewerKey)
            }
        }

        // 2. Escribir app.findaro.files en NSFileViewer global
        CFPreferencesSetValue(
            "NSFileViewer" as CFString,
            bundleID as CFPropertyList,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let synced = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        shared.refreshStatus()
        return synced
    }

    @discardableResult
    public static func disable() -> Bool {
        let previous = UserDefaults.standard.string(forKey: previousViewerKey)

        if let prev = previous, !prev.isEmpty, prev != bundleID {
            // Restaurar la app anterior registrada (ej. com.cocoatech.PathFinder o com.binarynights.ForkLift)
            CFPreferencesSetValue(
                "NSFileViewer" as CFString,
                prev as CFPropertyList,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        } else {
            // Si no había valor anterior (era Finder nativo), eliminar la clave
            CFPreferencesSetValue(
                "NSFileViewer" as CFString,
                nil,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        UserDefaults.standard.removeObject(forKey: previousViewerKey)
        let synced = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        shared.refreshStatus()
        return synced
    }

    public static func installedAppURL() -> URL? {
        let candidates = [
            Bundle.main.bundleURL,
            URL(fileURLWithPath: "/Applications/Findaro.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Findaro.app")
        ]
        for url in candidates {
            if url.path.hasSuffix(".app"), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    public static func uninstallApp() {
        _ = disable()
        if let appURL = installedAppURL() {
            try? FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
        }
    }

    /// Registra el manejador de Apple Events en applicationWillFinishLaunching
    public func install() {
        // Event Class: 'misc' (0x6d697363), Event ID: 'mvis' (0x6d766973)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleRevealAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(0x6d697363),
            andEventID: AEEventID(0x6d766973)
        )
    }

    @objc private func handleRevealAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let directObject = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        var urls: [URL] = []

        if directObject.numberOfItems > 0 {
            for i in 1...directObject.numberOfItems {
                if let item = directObject.atIndex(i), let url = extractURL(from: item) {
                    urls.append(url)
                }
            }
        } else if let url = extractURL(from: directObject) {
            urls.append(url)
        }

        guard !urls.isEmpty else { return }

        let paths = urls.map { $0.standardizedFileURL.path }
        DispatchQueue.main.async {
            Self.revealPaths(paths)
        }
    }

    private func extractURL(from descriptor: NSAppleEventDescriptor) -> URL? {
        if let url = descriptor.fileURLValue {
            return url
        }
        if let str = descriptor.stringValue, !str.isEmpty {
            if str.hasPrefix("file://") {
                return URL(string: str)
            }
            return URL(fileURLWithPath: str)
        }
        return nil
    }

    public static func revealPaths(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        pendingRevealPaths = paths
        NotificationCenter.default.post(name: .findaroRevealPaths, object: paths)
        // Solo activar la app: la capa UI reusa UNA ventana de explorador
        // (traer todas al frente producía multi-Findaro + fantasmas transparentes).
        if let app = NSApplication.value(forKey: "sharedApplication") as? NSApplication {
            app.activate(ignoringOtherApps: true)
        }
    }
}

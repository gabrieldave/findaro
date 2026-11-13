import AppKit

@MainActor
public enum DropoverBridge {
    public static let bundleIdentifier = "me.damir.dropover-mac"

    /// Localiza Dropover.app en la Mac por Bundle ID o en carpetas de Aplicaciones.
    public static func locateDropoverURL() -> URL? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return appURL
        }
        let candidates = [
            URL(fileURLWithPath: "/Applications/Dropover.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Dropover.app", isDirectory: true)
        ]
        for url in candidates {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Indica si Dropover está instalado en esta Mac.
    public static var isInstalled: Bool {
        locateDropoverURL() != nil
    }

    /// Abre los archivos/URLs seleccionados en Dropover.
    @discardableResult
    public static func send(urls: [URL], completion: (@MainActor (Bool, Error?) -> Void)? = nil) -> Bool {
        guard let dropoverURL = locateDropoverURL() else {
            completion?(false, NSError(
                domain: "app.findaro.dropover",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Dropover.app not found"]
            ))
            return false
        }
        guard !urls.isEmpty else {
            completion?(false, nil)
            return false
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: dropoverURL, configuration: config) { _, error in
            Task { @MainActor in
                completion?(error == nil, error)
            }
        }
        return true
    }
}

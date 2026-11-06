import Foundation

/// Preferencias propias — no dependemos del amnésico .DS_Store del Finder.
public struct OrdenPreferences: Codable, Equatable, Sendable {
    public var globalRule: SortRule
    public var folderOverrides: [String: SortRule]
    public var favorites: [String]
    public var lastPath: String?

    public init(
        globalRule: SortRule = .default,
        folderOverrides: [String: SortRule] = [:],
        favorites: [String] = [],
        lastPath: String? = nil
    ) {
        self.globalRule = globalRule
        self.folderOverrides = folderOverrides
        self.favorites = favorites
        self.lastPath = lastPath
    }

    public func rule(for path: String) -> SortRule {
        if let override = folderOverrides[path] {
            return override
        }
        // Perfiles sensatos por carpeta conocida
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == (home as NSString).appendingPathComponent("Downloads") {
            return folderOverrides[path] ?? .downloads
        }
        return globalRule
    }
}

public final class PreferencesStore: @unchecked Sendable {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public private(set) var preferences: OrdenPreferences

    public init(fileName: String = "preferences.json") {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Orden", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(fileName)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(OrdenPreferences.self, from: data) {
            preferences = decoded
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            preferences = OrdenPreferences(
                globalRule: .default,
                folderOverrides: [
                    (home as NSString).appendingPathComponent("Downloads"): .downloads,
                    (home as NSString).appendingPathComponent("Documents"): .projects
                ],
                favorites: [
                    (home as NSString).appendingPathComponent("Downloads"),
                    (home as NSString).appendingPathComponent("Desktop"),
                    (home as NSString).appendingPathComponent("Documents"),
                    (home as NSString).appendingPathComponent("Projects")
                ],
                lastPath: (home as NSString).appendingPathComponent("Downloads")
            )
            save()
        }
    }

    public func update(_ mutate: (inout OrdenPreferences) -> Void) {
        mutate(&preferences)
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(preferences) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

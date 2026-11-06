import Foundation

/// Preferencias propias — no dependemos del amnésico .DS_Store del Finder.
public struct OrdenPreferences: Codable, Equatable, Sendable {
    /// 6 = tipos juntos + Agregado ↓ dentro (zip no entre .md)
    public var schemaVersion: Int
    public var globalRule: SortRule
    public var folderOverrides: [String: SortRule]
    public var favorites: [String]
    public var lastPath: String?

    public init(
        schemaVersion: Int = 2,
        globalRule: SortRule = .default,
        folderOverrides: [String: SortRule] = [:],
        favorites: [String] = [],
        lastPath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.globalRule = globalRule
        self.folderOverrides = folderOverrides
        self.favorites = favorites
        self.lastPath = lastPath
    }

    public func rule(for path: String) -> SortRule {
        if let override = folderOverrides[path] {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == (home as NSString).appendingPathComponent("Downloads") {
            return .downloads
        }
        if path == (home as NSString).appendingPathComponent("Documents")
            || path == (home as NSString).appendingPathComponent("Projects") {
            return .projects
        }
        return globalRule
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, globalRule, folderOverrides, favorites, lastPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        globalRule = try c.decodeIfPresent(SortRule.self, forKey: .globalRule) ?? .default
        folderOverrides = try c.decodeIfPresent([String: SortRule].self, forKey: .folderOverrides) ?? [:]
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        lastPath = try c.decodeIfPresent(String.self, forKey: .lastPath)
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
            preferences = Self.migrate(decoded)
            if preferences != decoded {
                save()
            }
        } else {
            preferences = Self.freshDefaults()
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

    private static func freshDefaults() -> OrdenPreferences {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return OrdenPreferences(
            schemaVersion: 6,
            globalRule: .default,
            folderOverrides: [
                (home as NSString).appendingPathComponent("Downloads"): .downloads,
                (home as NSString).appendingPathComponent("Documents"): .projects,
                (home as NSString).appendingPathComponent("Projects"): .projects
            ],
            favorites: [
                (home as NSString).appendingPathComponent("Downloads"),
                (home as NSString).appendingPathComponent("Desktop"),
                (home as NSString).appendingPathComponent("Documents"),
                (home as NSString).appendingPathComponent("Projects")
            ],
            lastPath: (home as NSString).appendingPathComponent("Downloads")
        )
    }

    /// Actualiza el override de Descargas al perfil smart si venía del MVP v1.
    private static func migrate(_ prefs: OrdenPreferences) -> OrdenPreferences {
        var next = prefs
        let downloads = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent("Downloads")

        if next.schemaVersion < 2 {
            next.folderOverrides[downloads] = .downloads
            if next.folderOverrides[(FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent("Projects")] == nil {
                next.folderOverrides[(FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                    .appendingPathComponent("Projects")] = .projects
            }
            next.schemaVersion = 2
        }
        if next.schemaVersion < 3 {
            next.folderOverrides[downloads] = .downloads
            next.schemaVersion = 3
        }
        if next.schemaVersion < 4 {
            next.folderOverrides[downloads] = .downloads
            next.schemaVersion = 4
        }
        if next.schemaVersion < 5 {
            next.globalRule = .newestAddedFirst
            next.folderOverrides[downloads] = .downloads
            next.schemaVersion = 5
        }
        if next.schemaVersion < 6 {
            next.globalRule = .downloads
            next.folderOverrides[downloads] = .downloads
            next.schemaVersion = 6
        }
        return next
    }
}

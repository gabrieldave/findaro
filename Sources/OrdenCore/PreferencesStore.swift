import Foundation

/// Preferencias propias — no dependemos del amnésico .DS_Store del Finder.
public struct OrdenPreferences: Codable, Equatable, Sendable {
    /// 8 = estilo Descargas es el global; overrides solo si la carpeta pide orden propio
    public var schemaVersion: Int
    public var globalRule: SortRule
    /// Solo carpetas con orden distinto al global.
    public var folderOverrides: [String: SortRule]
    public var favorites: [String]
    public var lastPath: String?

    public init(
        schemaVersion: Int = 8,
        globalRule: SortRule = .downloads,
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

    /// Override de carpeta si existe; si no, el global (estilo Descargas por defecto).
    public func rule(for path: String) -> SortRule {
        folderOverrides[path] ?? globalRule
    }

    public func hasOverride(for path: String) -> Bool {
        folderOverrides[path] != nil
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, globalRule, folderOverrides, favorites, lastPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        globalRule = try c.decodeIfPresent(SortRule.self, forKey: .globalRule) ?? .downloads
        folderOverrides = try c.decodeIfPresent([String: SortRule].self, forKey: .folderOverrides) ?? [:]
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        lastPath = try c.decodeIfPresent(String.self, forKey: .lastPath)
    }
}

public enum SortSaveScope: String, Sendable {
    /// Solo esta carpeta guarda su propio orden.
    case thisFolder
    /// Queda como default en todas (borra overrides).
    case everywhere
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
            schemaVersion: 8,
            globalRule: .downloads,
            folderOverrides: [:],
            favorites: [
                (home as NSString).appendingPathComponent("Downloads"),
                (home as NSString).appendingPathComponent("Desktop"),
                (home as NSString).appendingPathComponent("Documents"),
                (home as NSString).appendingPathComponent("Projects")
            ],
            lastPath: (home as NSString).appendingPathComponent("Downloads")
        )
    }

    private static func migrate(_ prefs: OrdenPreferences) -> OrdenPreferences {
        var next = prefs
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let downloads = (home as NSString).appendingPathComponent("Downloads")

        // Migraciones previas (idempotentes en espíritu).
        if next.schemaVersion < 7 {
            next.globalRule = .downloads
            next.folderOverrides[downloads] = .downloads
            next.schemaVersion = 7
        }
        if next.schemaVersion < 8 {
            // Estilo Descargas = default global. Sin overrides especiales de Documents/Projects.
            next.globalRule = .downloads
            next.folderOverrides = [:]
            next.schemaVersion = 8
        }
        return next
    }
}

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
    public var viewMode: BrowserViewMode
    /// Mostrar la ruta completa bajo el nombre en la lista.
    public var showRowPaths: Bool
    /// Enter abre / F2 renombra (perfil tipo Explorer).
    public var explorerKeyboardProfile: Bool
    /// Mostrar archivos/carpetas ocultos (punto / flag hidden).
    public var showHiddenFiles: Bool
    /// Lista plana de archivos bajo la carpeta actual (sin jerarquía).
    public var flattenFolderView: Bool
    /// Atajos del asistente (tipo + fecha). Muchos → UI scrolleable.
    public var assistantShortcuts: [AssistantShortcut]
    /// Fase 3: usar Ollama si está corriendo (opt-in).
    public var ollamaEnabled: Bool
    public var ollamaModel: String
    /// Plantillas de vista (orden + modo + filtro) para reaplicar cuando quieras.
    public var viewTemplates: [ViewTemplate]
    /// Overrides de atajos de teclado (id → acorde). Vacío = defaults de fábrica.
    public var keyboardHotkeyOverrides: [String: KeyChord]
    /// Carpeta que abre el atajo global ⌃⌥O. `nil` = Descargas.
    public var globalHotkeyFolderPath: String?
    /// Idioma de la interfaz (auto, es, en).
    public var appLanguage: AppLanguage
    /// Carpetas inteligentes (búsquedas guardadas) que aparecen en Favoritos.
    public var smartFolders: [SmartFolder]

    public init(
        schemaVersion: Int = 17,
        globalRule: SortRule = .downloads,
        folderOverrides: [String: SortRule] = [:],
        favorites: [String] = [],
        lastPath: String? = nil,
        viewMode: BrowserViewMode = .list,
        showRowPaths: Bool = true,
        explorerKeyboardProfile: Bool = false,
        showHiddenFiles: Bool = false,
        flattenFolderView: Bool = false,
        assistantShortcuts: [AssistantShortcut] = AssistantShortcut.factoryDefaults(),
        ollamaEnabled: Bool = false,
        ollamaModel: String = "qwen2.5:3b",
        viewTemplates: [ViewTemplate] = ViewTemplate.factoryDefaults(),
        keyboardHotkeyOverrides: [String: KeyChord] = [:],
        globalHotkeyFolderPath: String? = nil,
        appLanguage: AppLanguage = .english,
        smartFolders: [SmartFolder] = []
    ) {
        self.schemaVersion = schemaVersion
        self.globalRule = globalRule
        self.folderOverrides = folderOverrides
        self.favorites = favorites
        self.lastPath = lastPath
        self.viewMode = viewMode
        self.showRowPaths = showRowPaths
        self.explorerKeyboardProfile = explorerKeyboardProfile
        self.showHiddenFiles = showHiddenFiles
        self.flattenFolderView = flattenFolderView
        self.assistantShortcuts = assistantShortcuts
        self.ollamaEnabled = ollamaEnabled
        self.ollamaModel = ollamaModel
        self.viewTemplates = viewTemplates
        self.keyboardHotkeyOverrides = keyboardHotkeyOverrides
        self.globalHotkeyFolderPath = globalHotkeyFolderPath
        self.appLanguage = appLanguage
        self.smartFolders = smartFolders
    }

    /// Override de carpeta si existe; si no, el global (estilo Descargas por defecto).
    public func rule(for path: String) -> SortRule {
        let key = (path as NSString).standardizingPath
        return folderOverrides[key] ?? folderOverrides[path] ?? globalRule
    }

    public func hasOverride(for path: String) -> Bool {
        let key = (path as NSString).standardizingPath
        return folderOverrides[key] != nil || folderOverrides[path] != nil
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, globalRule, folderOverrides, favorites, lastPath, viewMode, showRowPaths,
             explorerKeyboardProfile, showHiddenFiles, flattenFolderView, assistantShortcuts,
             ollamaEnabled, ollamaModel, viewTemplates, keyboardHotkeyOverrides, globalHotkeyFolderPath,
             appLanguage, smartFolders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        globalRule = try c.decodeIfPresent(SortRule.self, forKey: .globalRule) ?? .downloads
        folderOverrides = try c.decodeIfPresent([String: SortRule].self, forKey: .folderOverrides) ?? [:]
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        lastPath = try c.decodeIfPresent(String.self, forKey: .lastPath)
        viewMode = try c.decodeIfPresent(BrowserViewMode.self, forKey: .viewMode) ?? .list
        showRowPaths = try c.decodeIfPresent(Bool.self, forKey: .showRowPaths) ?? true
        explorerKeyboardProfile = try c.decodeIfPresent(Bool.self, forKey: .explorerKeyboardProfile) ?? false
        showHiddenFiles = try c.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        flattenFolderView = try c.decodeIfPresent(Bool.self, forKey: .flattenFolderView) ?? false
        assistantShortcuts = try c.decodeIfPresent([AssistantShortcut].self, forKey: .assistantShortcuts)
            ?? AssistantShortcut.factoryDefaults()
        ollamaEnabled = try c.decodeIfPresent(Bool.self, forKey: .ollamaEnabled) ?? false
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "qwen2.5:3b"
        viewTemplates = try c.decodeIfPresent([ViewTemplate].self, forKey: .viewTemplates)
            ?? ViewTemplate.factoryDefaults()
        keyboardHotkeyOverrides = try c.decodeIfPresent([String: KeyChord].self, forKey: .keyboardHotkeyOverrides) ?? [:]
        globalHotkeyFolderPath = try c.decodeIfPresent(String.self, forKey: .globalHotkeyFolderPath)
        let decodedLang = try c.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .english
        appLanguage = (decodedLang == .auto) ? .english : decodedLang
        // Tolerante: si el bloque falla, no se pierde el resto de preferencias.
        smartFolders = (try? c.decodeIfPresent([SmartFolder].self, forKey: .smartFolders)) ?? []
    }
}

public enum SortSaveScope: String, Sendable {
    /// Solo esta carpeta guarda su propio orden.
    case thisFolder
    /// Queda como default en todas (borra overrides).
    case everywhere
}

public final class PreferencesStore: @unchecked Sendable {
    public static let shared = PreferencesStore()

    private let lock = NSLock()
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var _preferences: OrdenPreferences
    public var preferences: OrdenPreferences {
        lock.lock()
        defer { lock.unlock() }
        return _preferences
    }

    public init(fileName: String = "preferences.json", directory: URL? = nil) {
        let dir: URL
        if let custom = directory {
            dir = custom
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = support.appendingPathComponent("Ordena", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(fileName)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(OrdenPreferences.self, from: data) {
            _preferences = Self.migrate(decoded)
            if _preferences != decoded {
                save()
            }
        } else {
            _preferences = Self.freshDefaults()
            save()
        }
    }

    /// Notificación de broadcast para sincronización reactiva entre instancias (Ajustes, pestañas, ventanas).
    public static let preferencesDidChangeNotification = Notification.Name("app.findaro.preferencesDidChange")

    /// Último error de persistencia (nil = OK). La UI puede mostrar `lastSaveError`.
    private var _lastSaveError: String?
    public var lastSaveError: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastSaveError
    }

    /// Recarga las preferencias desde el archivo en disco.
    @discardableResult
    public func reloadFromDisk() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(OrdenPreferences.self, from: data) else {
            return false
        }
        _preferences = Self.migrate(decoded)
        return true
    }

    public func update(_ mutate: (inout OrdenPreferences) -> Void) {
        var didSave = false
        lock.lock()
        mutate(&_preferences)
        do {
            let data = try encoder.encode(_preferences)
            try data.write(to: url, options: .atomic)
            _lastSaveError = nil
            didSave = true
        } catch {
            _lastSaveError = error.localizedDescription
        }
        lock.unlock()
        if didSave {
            NotificationCenter.default.post(name: Self.preferencesDidChangeNotification, object: self)
        }
    }

    /// Guarda y propaga el error (tests / callers que deben fallar cerrado).
    public func saveThrowing() throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try encoder.encode(_preferences)
        try data.write(to: url, options: .atomic)
    }

    private func save() {
        lock.lock()
        defer { lock.unlock() }
        do {
            let data = try encoder.encode(_preferences)
            try data.write(to: url, options: .atomic)
            _lastSaveError = nil
        } catch {
            _lastSaveError = error.localizedDescription
        }
    }

    private static func freshDefaults() -> OrdenPreferences {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return OrdenPreferences(
            schemaVersion: 17,
            globalRule: .downloads,
            folderOverrides: [:],
            favorites: [
                (home as NSString).appendingPathComponent("Downloads"),
                (home as NSString).appendingPathComponent("Desktop"),
                (home as NSString).appendingPathComponent("Documents"),
                (home as NSString).appendingPathComponent("Projects")
            ],
            lastPath: (home as NSString).appendingPathComponent("Downloads"),
            showRowPaths: true,
            explorerKeyboardProfile: false,
            showHiddenFiles: false,
            flattenFolderView: false,
            viewTemplates: ViewTemplate.factoryDefaults(),
            appLanguage: .english
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
        if next.schemaVersion < 9 {
            next.viewMode = .list
            next.schemaVersion = 9
        }
        if next.schemaVersion < 10 {
            next.showRowPaths = true
            next.schemaVersion = 10
        }
        if next.schemaVersion < 11 {
            next.explorerKeyboardProfile = false
            next.schemaVersion = 11
        }
        if next.schemaVersion < 12 {
            if next.assistantShortcuts.isEmpty {
                next.assistantShortcuts = AssistantShortcut.factoryDefaults()
            }
            next.ollamaEnabled = false
            if next.ollamaModel.isEmpty {
                next.ollamaModel = "qwen2.5:3b"
            }
            next.schemaVersion = 12
        }
        if next.schemaVersion < 13 {
            if next.viewTemplates.isEmpty {
                next.viewTemplates = ViewTemplate.factoryDefaults()
            }
            next.schemaVersion = 13
        }
        if next.schemaVersion < 14 {
            next.showHiddenFiles = false
            next.flattenFolderView = false
            next.schemaVersion = 14
        }
        if next.schemaVersion < 15 {
            next.keyboardHotkeyOverrides = [:]
            next.schemaVersion = 15
        }
        if next.schemaVersion < 16 {
            next.globalHotkeyFolderPath = nil
            next.schemaVersion = 16
        }
        if next.schemaVersion < 17 {
            // Default global to English for all installs
            next.appLanguage = .english
            next.schemaVersion = 17
        }
        // Tope duro: gente crea muchos; no dejamos crecer sin límite.
        if next.assistantShortcuts.count > AssistantShortcut.maxCount {
            next.assistantShortcuts = Array(next.assistantShortcuts.prefix(AssistantShortcut.maxCount))
        }
        if next.smartFolders.count > SmartFolder.maxCount {
            next.smartFolders = Array(next.smartFolders.prefix(SmartFolder.maxCount))
        }
        if next.viewTemplates.count > ViewTemplate.maxCount {
            next.viewTemplates = Array(next.viewTemplates.prefix(ViewTemplate.maxCount))
        }
        return next
    }
}

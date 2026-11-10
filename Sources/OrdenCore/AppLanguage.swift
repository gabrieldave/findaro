import Foundation

/// Idioma de la interfaz de Findaro.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case auto = "auto"
    case spanish = "es"
    case english = "en"

    public var displayName: String {
        switch self {
        case .auto:
            return isEnglish ? "Automatic (System)" : "Automático (Sistema)"
        case .spanish:
            return "Español"
        case .english:
            return "English"
        }
    }

    /// Inglés efectivo de la UI. En `.auto` sigue el idioma preferido del Mac (`es*` → español).
    public var isEnglish: Bool {
        switch self {
        case .english:
            return true
        case .spanish:
            return false
        case .auto:
            return Self.systemPrefersEnglish
        }
    }

    /// `true` si el sistema prefiere inglés (o un idioma no español).
    public static var systemPrefersEnglish: Bool {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return !preferred.hasPrefix("es")
    }
}

/// Central de textos localizados para Findaro (Español / Inglés).
public enum L10n {
    public nonisolated(unsafe) static var activeLanguage: AppLanguage = .english

    public static func s(_ es: String, _ en: String) -> String {
        activeLanguage.isEnglish ? en : es
    }

    public static var isEnglish: Bool {
        activeLanguage.isEnglish
    }

    // MARK: - Strings comunes
    public static var appTitle: String { s("Findaro", "Findaro") }
    public static var searchPlaceholder: String { s("Buscar archivos o atajos…", "Search files or shortcuts…") }
    public static var dualPane: String { s("2 paneles", "Dual pane") }
    public static var singlePane: String { s("1 panel", "Single pane") }
    public static var newFolder: String { s("Nueva carpeta", "New folder") }
    public static var newFile: String { s("Nuevo archivo", "New file") }
    public static var trash: String { s("Papelera", "Trash") }
    public static var restore: String { s("Restaurar", "Restore") }
    public static var deletePermanently: String { s("Eliminar para siempre", "Delete permanently") }
    public static var cancel: String { s("Cancelar", "Cancel") }
    public static var go: String { s("Ir", "Go") }
    public static var search: String { s("Buscar", "Search") }
    public static var searchInSubfolders: String { s("Buscar en subcarpetas", "Search in subfolders") }
    public static var goToFolderOrFile: String { s("Ir a carpeta o archivo", "Go to folder or file") }
    public static var smartMerge: String { s("Fusionar carpetas", "Smart Merge") }
    public static var keepBoth: String { s("Conservar ambos", "Keep both") }
    public static var replace: String { s("Reemplazar", "Replace") }
    public static var aiAssistant: String { s("Asistente IA", "AI Assistant") }
    public static var listening: String { s("Escuchando…", "Listening…") }
    public static var sendToModel: String { s("Enviar a modelo", "Send to model") }
    public static var configureOllama: String { s("Configurar Ollama…", "Configure Ollama…") }
    public static var settings: String { s("Preferencias", "Settings") }
    public static var language: String { s("Idioma", "Language") }
}

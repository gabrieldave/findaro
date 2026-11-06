import Foundation

/// Vistas tipo Finder.
public enum BrowserViewMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case icons
    case list
    case columns
    case gallery

    public var id: String { rawValue }

    public var labelSpanish: String {
        switch self {
        case .icons: return "Iconos"
        case .list: return "Lista"
        case .columns: return "Columnas"
        case .gallery: return "Galería"
        }
    }

    /// SF Symbol aproximado al control de Finder.
    public var symbolName: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        case .gallery: return "rectangle.bottomthird.inset.filled"
        }
    }
}

import Foundation
import CoreGraphics

/// Columnas opcionales de la vista lista (el Nombre siempre está).
public enum ListColumn: String, Codable, Sendable, CaseIterable, Identifiable {
    case kind
    case dateAdded
    case dateModified
    case dateCreated
    case dateLastOpened
    case size

    public var id: String { rawValue }

    public var labelSpanish: String {
        switch self {
        case .kind: return "Clase"
        case .dateAdded: return "Fecha en que se agregó"
        case .dateModified: return "Fecha de modificación"
        case .dateCreated: return "Fecha de creación"
        case .dateLastOpened: return "Fecha de última apertura"
        case .size: return "Tamaño"
        }
    }

    public var labelEnglish: String {
        switch self {
        case .kind: return "Kind"
        case .dateAdded: return "Date Added"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        case .dateLastOpened: return "Date Last Opened"
        case .size: return "Size"
        }
    }

    public var labelLocalized: String {
        L10n.isEnglish ? labelEnglish : labelSpanish
    }

    public var shortLabelSpanish: String {
        switch self {
        case .kind: return "Clase"
        case .dateAdded: return "Agregado"
        case .dateModified: return "Modificado"
        case .dateCreated: return "Creado"
        case .dateLastOpened: return "Abierto"
        case .size: return "Tamaño"
        }
    }

    public var shortLabelEnglish: String {
        switch self {
        case .kind: return "Kind"
        case .dateAdded: return "Added"
        case .dateModified: return "Modified"
        case .dateCreated: return "Created"
        case .dateLastOpened: return "Opened"
        case .size: return "Size"
        }
    }

    public var shortLabelLocalized: String {
        L10n.isEnglish ? shortLabelEnglish : shortLabelSpanish
    }

    public var width: CGFloat {
        switch self {
        case .kind: return 100
        case .dateAdded, .dateModified, .dateCreated, .dateLastOpened: return 130
        case .size: return 84
        }
    }

    public var compactWidth: CGFloat {
        switch self {
        case .kind: return 0 // oculto en compacto salvo size/dates
        case .dateAdded, .dateModified, .dateCreated, .dateLastOpened: return 108
        case .size: return 72
        }
    }

    /// Por defecto: Clase + Agregado + Tamaño (como ahora).
    public static let defaultVisible: [ListColumn] = [.kind, .dateAdded, .size]

    public static func sanitize(_ columns: [ListColumn]) -> [ListColumn] {
        var seen = Set<ListColumn>()
        var out: [ListColumn] = []
        for c in columns where seen.insert(c).inserted {
            out.append(c)
        }
        return out.isEmpty ? defaultVisible : out
    }

    public static func totalWidth(_ columns: [ListColumn], compact: Bool) -> CGFloat {
        columns.reduce(0) { partial, col in
            let w = compact ? col.compactWidth : col.width
            return partial + (w > 0 ? w + 12 : 0)
        }
    }
}

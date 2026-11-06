import Foundation

/// Una sola idea de orden — sin pelear Arrange / Group / Sort.
public struct SortRule: Codable, Equatable, Sendable, Hashable {
    public var keys: [SortKey]
    /// Si está definido, las carpetas usan estas claves (p. ej. Nombre en Descargas).
    public var folderKeys: [SortKey]?
    /// Si está definido, los archivos usan estas claves (p. ej. Fecha agregada).
    public var fileKeys: [SortKey]?
    public var foldersFirst: Bool
    public var groupBy: GroupBy?
    /// Si true: los bloques de tipo se ordenan por el Agregado más reciente del bloque
    /// (vídeos viejos abajo; textos nuevos arriba). Dentro del bloque: fileKeys.
    public var orderCategoriesByRecency: Bool

    public init(
        keys: [SortKey] = [.name(ascending: true)],
        folderKeys: [SortKey]? = nil,
        fileKeys: [SortKey]? = nil,
        foldersFirst: Bool = true,
        groupBy: GroupBy? = nil,
        orderCategoriesByRecency: Bool = false
    ) {
        self.keys = keys.isEmpty ? [.name(ascending: true)] : keys
        self.folderKeys = folderKeys
        self.fileKeys = fileKeys
        self.foldersFirst = foldersFirst
        self.groupBy = groupBy
        self.orderCategoriesByRecency = orderCategoriesByRecency
    }

    /// Agregado · lo más nuevo arriba (puede mezclar tipos si las fechas se cruzan).
    public static let newestAddedFirst = SortRule(
        keys: [
            .dateAdded(ascending: false),
            .name(ascending: true)
        ],
        foldersFirst: true
    )

    /// Por defecto = Descargas: tipos juntos + dentro lo más nuevo arriba.
    public static let `default` = SortRule.downloads

    /// Descargas: carpetas Agregado ↓; archivos por tipo juntos;
    /// bloques de tipo ordenados por lo más reciente del bloque; dentro Agregado ↓.
    public static let downloads = SortRule(
        keys: [
            .dateAdded(ascending: false),
            .name(ascending: true)
        ],
        folderKeys: [
            .dateAdded(ascending: false),
            .name(ascending: true)
        ],
        fileKeys: [
            .dateAdded(ascending: false),
            .name(ascending: true)
        ],
        foldersFirst: true,
        orderCategoriesByRecency: true
    )

    public static let projects = SortRule(
        keys: [.name(ascending: true)],
        foldersFirst: true
    )

    /// Por tipo de archivo (vídeo, Excel, PDF…) y luego nombre.
    public static let byType = SortRule(
        keys: [.category(ascending: true), .name(ascending: true)],
        foldersFirst: true
    )

    /// Limpieza: lo más pesado arriba (carpetas y archivos).
    public static let heaviestFirst = SortRule(
        keys: [
            .size(ascending: false),
            .name(ascending: true)
        ],
        foldersFirst: false
    )

    public var usesSplitKeys: Bool {
        folderKeys != nil || fileKeys != nil
    }

    /// Frase legible para la barra.
    public var summarySpanish: String {
        var parts: [String] = []
        if foldersFirst {
            parts.append("Carpetas arriba")
        }

        if usesSplitKeys {
            let folders = (folderKeys ?? keys).map(\.summarySpanish).joined(separator: ", ")
            let files = (fileKeys ?? keys).map(\.summarySpanish).joined(separator: ", ")
            parts.append("carpetas \(folders)")
            parts.append("archivos \(files)")
            if (folderKeys ?? []).contains(where: { if case .name = $0 { return true }; return false }) {
                parts.append("números naturales")
            }
        } else {
            for key in keys {
                parts.append(key.summarySpanish)
            }
            if keys.contains(where: {
                if case .name = $0 { return true }
                return false
            }) {
                parts.append("números naturales")
            }
        }

        if orderCategoriesByRecency {
            parts.append("tipos juntos (bloque reciente primero)")
            parts.append("dentro Agregado ↓")
        }

        if let groupBy {
            parts.append("agrupado por \(groupBy.summarySpanish)")
        }
        return parts.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case keys, folderKeys, fileKeys, foldersFirst, groupBy, orderCategoriesByRecency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = try c.decodeIfPresent([SortKey].self, forKey: .keys) ?? [.name(ascending: true)]
        if keys.isEmpty { keys = [.name(ascending: true)] }
        folderKeys = try c.decodeIfPresent([SortKey].self, forKey: .folderKeys)
        fileKeys = try c.decodeIfPresent([SortKey].self, forKey: .fileKeys)
        foldersFirst = try c.decodeIfPresent(Bool.self, forKey: .foldersFirst) ?? true
        groupBy = try c.decodeIfPresent(GroupBy.self, forKey: .groupBy)
        orderCategoriesByRecency = try c.decodeIfPresent(Bool.self, forKey: .orderCategoriesByRecency) ?? false
    }

    /// Claves efectivas al comparar dos entradas del mismo tipo.
    public func keysForComparing(isDirectory: Bool) -> [SortKey] {
        if isDirectory {
            return folderKeys ?? keys
        }
        return fileKeys ?? keys
    }
}

public enum SortKey: Codable, Equatable, Sendable, Hashable {
    case name(ascending: Bool)
    case dateModified(ascending: Bool)
    case dateCreated(ascending: Bool)
    case dateAdded(ascending: Bool)
    case size(ascending: Bool)
    case kind(ascending: Bool)
    /// Categoría Orden (vídeo, Excel, PDF…) — no el “Kind” localizado del sistema.
    case category(ascending: Bool)

    public var summarySpanish: String {
        switch self {
        case .name(let ascending):
            return ascending ? "Nombre A→Z" : "Nombre Z→A"
        case .dateModified(let ascending):
            return ascending ? "Modificado ↑" : "Modificado ↓"
        case .dateCreated(let ascending):
            return ascending ? "Creado ↑" : "Creado ↓"
        case .dateAdded(let ascending):
            return ascending ? "Agregado ↑" : "Agregado ↓ (reciente primero)"
        case .size(let ascending):
            return ascending ? "Tamaño ↑" : "Tamaño ↓"
        case .kind(let ascending):
            return ascending ? "Clase A→Z" : "Clase Z→A"
        case .category(let ascending):
            return ascending ? "Tipo (vídeo, Excel…)" : "Tipo Z→A"
        }
    }

    public var isAscending: Bool {
        switch self {
        case .name(let a), .dateModified(let a), .dateCreated(let a),
             .dateAdded(let a), .size(let a), .kind(let a), .category(let a):
            return a
        }
    }
}

public enum GroupBy: String, Codable, Equatable, Sendable, Hashable {
    case kind
    case dayModified

    public var summarySpanish: String {
        switch self {
        case .kind: return "clase"
        case .dayModified: return "día de modificación"
        }
    }
}

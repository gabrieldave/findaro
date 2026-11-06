import Foundation

/// Una sola idea de orden — sin pelear Arrange / Group / Sort.
public struct SortRule: Codable, Equatable, Sendable, Hashable {
    public var keys: [SortKey]
    public var foldersFirst: Bool
    public var groupBy: GroupBy?

    public init(
        keys: [SortKey] = [.name(ascending: true)],
        foldersFirst: Bool = true,
        groupBy: GroupBy? = nil
    ) {
        self.keys = keys.isEmpty ? [.name(ascending: true)] : keys
        self.foldersFirst = foldersFirst
        self.groupBy = groupBy
    }

    public static let `default` = SortRule()

    public static let downloads = SortRule(
        keys: [.dateAdded(ascending: false)],
        foldersFirst: true
    )

    public static let projects = SortRule(
        keys: [.name(ascending: true)],
        foldersFirst: true
    )

    /// Frase legible para la barra: “Carpetas arriba · Nombre A→Z · números naturales”.
    public var summarySpanish: String {
        var parts: [String] = []
        if foldersFirst {
            parts.append("Carpetas arriba")
        }
        for key in keys {
            parts.append(key.summarySpanish)
        }
        if keys.contains(where: {
            if case .name = $0 { return true }
            return false
        }) {
            parts.append("números naturales")
        }
        if let groupBy {
            parts.append("agrupado por \(groupBy.summarySpanish)")
        }
        return parts.joined(separator: " · ")
    }
}

public enum SortKey: Codable, Equatable, Sendable, Hashable {
    case name(ascending: Bool)
    case dateModified(ascending: Bool)
    case dateCreated(ascending: Bool)
    case dateAdded(ascending: Bool)
    case size(ascending: Bool)
    case kind(ascending: Bool)

    public var summarySpanish: String {
        switch self {
        case .name(let ascending):
            return ascending ? "Nombre A→Z" : "Nombre Z→A"
        case .dateModified(let ascending):
            return ascending ? "Modificado ↑" : "Modificado ↓ (reciente primero)"
        case .dateCreated(let ascending):
            return ascending ? "Creado ↑" : "Creado ↓ (reciente primero)"
        case .dateAdded(let ascending):
            return ascending ? "Agregado ↑" : "Agregado ↓ (reciente primero)"
        case .size(let ascending):
            return ascending ? "Tamaño ↑" : "Tamaño ↓ (grandes primero)"
        case .kind(let ascending):
            return ascending ? "Clase A→Z" : "Clase Z→A"
        }
    }

    public var isAscending: Bool {
        switch self {
        case .name(let a), .dateModified(let a), .dateCreated(let a),
             .dateAdded(let a), .size(let a), .kind(let a):
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

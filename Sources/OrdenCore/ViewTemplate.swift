import Foundation

/// Plantilla de vista: cómo quieres ver los archivos (orden + modo + filtro de tipo).
public struct ViewTemplate: Codable, Equatable, Identifiable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var rule: SortRule
    public var viewMode: BrowserViewMode
    /// Si no es nil, solo muestra esa categoría (vídeo, PDF…).
    public var categoryFilter: FileCategory?
    public var createdAt: Date

    public static let maxCount = 24

    public init(
        id: UUID = UUID(),
        name: String,
        rule: SortRule,
        viewMode: BrowserViewMode = .list,
        categoryFilter: FileCategory? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rule = rule
        self.viewMode = viewMode
        self.categoryFilter = categoryFilter
        self.createdAt = createdAt
    }

    public var summarySpanish: String {
        var parts = [rule.summarySpanish, viewMode.labelSpanish.lowercased()]
        if let categoryFilter {
            parts.append("solo \(categoryFilter.labelSpanish)")
        }
        return parts.joined(separator: " · ")
    }

    /// Plantillas de fábrica (el usuario puede borrarlas o crear las suyas).
    public static func factoryDefaults() -> [ViewTemplate] {
        [
            ViewTemplate(name: "Más pesados", rule: .heaviestFirst, viewMode: .list),
            ViewTemplate(name: "Estilo Descargas", rule: .downloads, viewMode: .list),
            ViewTemplate(name: "Más nuevos", rule: .newestAddedFirst, viewMode: .list),
            ViewTemplate(name: "Por tipo", rule: .byType, viewMode: .list),
            ViewTemplate(
                name: "Nombre A→Z",
                rule: SortRule(keys: [.name(ascending: true)], foldersFirst: true),
                viewMode: .list
            )
        ]
    }
}

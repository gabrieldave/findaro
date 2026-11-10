import Foundation
import CoreGraphics

/// Filas de la lista agrupada por categoría (cabecera + archivos + hueco).
public enum ListPaneRow: Equatable, Sendable, Identifiable {
    case section(category: FileCategory, count: Int)
    case entry(FileEntry)
    /// Hueco entre categorías: marquesina / clic para seleccionar el bloque.
    case gap(category: FileCategory)

    public var id: String {
        switch self {
        case .section(let category, _): return "section:\(category.rawValue)"
        case .entry(let entry): return entry.id
        case .gap(let category): return "gap:\(category.rawValue)"
        }
    }

    public var entry: FileEntry? {
        if case .entry(let e) = self { return e }
        return nil
    }
}

public enum ListPaneLayout {
    public static let sectionHeight: CGFloat = 26
    public static let gapHeight: CGFloat = 16

    /// Agrupa por categoría (orden de primera aparición) con hueco entre bloques.
    public static func build(entries: [FileEntry]) -> [ListPaneRow] {
        guard !entries.isEmpty else { return [] }

        var order: [FileCategory] = []
        var buckets: [FileCategory: [FileEntry]] = [:]
        for entry in entries {
            if buckets[entry.category] == nil {
                order.append(entry.category)
            }
            buckets[entry.category, default: []].append(entry)
        }

        var rows: [ListPaneRow] = []
        for (index, category) in order.enumerated() {
            let group = buckets[category] ?? []
            rows.append(.section(category: category, count: group.count))
            for entry in group {
                rows.append(.entry(entry))
            }
            if index < order.count - 1 {
                rows.append(.gap(category: category))
            }
        }
        return rows
    }

    public static func height(of row: ListPaneRow, entryRowHeight: CGFloat) -> CGFloat {
        switch row {
        case .section: return sectionHeight
        case .gap: return gapHeight
        case .entry: return entryRowHeight
        }
    }

    public static func totalHeight(rows: [ListPaneRow], entryRowHeight: CGFloat) -> CGFloat {
        rows.reduce(0) { $0 + height(of: $1, entryRowHeight: entryRowHeight) }
    }

    /// Índice de fila de layout bajo Y (coordenadas del contenido).
    public static func rowIndexAtY(
        _ y: CGFloat,
        rows: [ListPaneRow],
        entryRowHeight: CGFloat
    ) -> Int? {
        guard !rows.isEmpty, y >= 0 else { return nil }
        var cursor: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let h = height(of: row, entryRowHeight: entryRowHeight)
            if y < cursor + h { return i }
            cursor += h
        }
        return nil
    }

    public static func entryAtY(
        _ y: CGFloat,
        rows: [ListPaneRow],
        entryRowHeight: CGFloat
    ) -> FileEntry? {
        guard let idx = rowIndexAtY(y, rows: rows, entryRowHeight: entryRowHeight) else { return nil }
        return rows[idx].entry
    }

    /// IDs de archivos tocados por el rectángulo vertical de marquesina.
    public static func entryIDs(
        y0: CGFloat,
        y1: CGFloat,
        rows: [ListPaneRow],
        entryRowHeight: CGFloat
    ) -> Set<String> {
        let lo = min(y0, y1)
        let hi = max(y0, y1)
        var cursor: CGFloat = 0
        var hits = Set<String>()
        for row in rows {
            let h = height(of: row, entryRowHeight: entryRowHeight)
            let top = cursor
            let bottom = cursor + h
            if bottom > lo, top < hi, case .entry(let entry) = row {
                hits.insert(entry.id)
            }
            cursor = bottom
        }
        return hits
    }

    public static func entries(inCategory category: FileCategory, from entries: [FileEntry]) -> [FileEntry] {
        entries.filter { $0.category == category }
    }
}

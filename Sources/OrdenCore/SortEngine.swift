import Foundation

/// Motor de orden determinista. Vista previa y lista usan la misma función.
public enum SortEngine {
    public static func sort(_ entries: [FileEntry], by rule: SortRule) -> [FileEntry] {
        let comparator = makeComparator(rule: rule)
        return entries.sorted(by: comparator)
    }

    public static func makeComparator(rule: SortRule) -> (FileEntry, FileEntry) -> Bool {
        { lhs, rhs in
            if rule.foldersFirst, lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            // Mismo tipo (o sin carpetas-arriba): claves por tipo si hay split.
            let keys: [SortKey]
            if lhs.isDirectory == rhs.isDirectory {
                keys = rule.keysForComparing(isDirectory: lhs.isDirectory)
            } else {
                keys = rule.keys
            }

            for key in keys {
                let cmp = compare(lhs, rhs, by: key)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
            }
            // Desempate estable: ruta
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    public static func compare(_ lhs: FileEntry, _ rhs: FileEntry, by key: SortKey) -> ComparisonResult {
        let raw: ComparisonResult
        switch key {
        case .name:
            raw = naturalCompare(lhs.name, rhs.name)
        case .dateModified:
            raw = compareDates(lhs.dateModified, rhs.dateModified)
        case .dateCreated:
            raw = compareDates(lhs.dateCreated, rhs.dateCreated)
        case .dateAdded:
            raw = compareDates(lhs.dateAdded, rhs.dateAdded)
        case .size:
            if lhs.size < rhs.size { raw = .orderedAscending }
            else if lhs.size > rhs.size { raw = .orderedDescending }
            else { raw = .orderedSame }
        case .kind:
            raw = lhs.kind.localizedStandardCompare(rhs.kind)
        case .category:
            if lhs.category.sortIndex < rhs.category.sortIndex {
                raw = .orderedAscending
            } else if lhs.category.sortIndex > rhs.category.sortIndex {
                raw = .orderedDescending
            } else {
                raw = .orderedSame
            }
        }

        return key.isAscending ? raw : invert(raw)
    }

    /// Orden natural: `file2` antes que `file10`. Usa collator del sistema.
    public static func naturalCompare(_ a: String, _ b: String) -> ComparisonResult {
        a.localizedStandardCompare(b)
    }

    private static func compareDates(_ a: Date, _ b: Date) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }

    private static func invert(_ result: ComparisonResult) -> ComparisonResult {
        switch result {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

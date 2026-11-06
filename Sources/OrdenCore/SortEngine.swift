import Foundation

/// Motor de orden determinista. Vista previa y lista usan la misma función.
public enum SortEngine {
    public static func sort(_ entries: [FileEntry], by rule: SortRule) -> [FileEntry] {
        if rule.orderCategoriesByRecency {
            return sortGroupingCategoriesByRecency(entries, rule: rule)
        }
        let comparator = makeComparator(rule: rule)
        return entries.sorted(by: comparator)
    }

    /// Carpetas con folderKeys; archivos agrupados por categoría;
    /// bloques ordenados por el Agregado más reciente del bloque (↓);
    /// dentro del bloque, fileKeys.
    private static func sortGroupingCategoriesByRecency(
        _ entries: [FileEntry],
        rule: SortRule
    ) -> [FileEntry] {
        let folders = entries.filter(\.isDirectory)
        let files = entries.filter { !$0.isDirectory }

        let folderRule = SortRule(
            keys: rule.folderKeys ?? rule.keys,
            foldersFirst: false
        )
        let sortedFolders = folders.sorted(by: makeComparator(rule: folderRule))

        var buckets: [FileCategory: [FileEntry]] = [:]
        for file in files {
            buckets[file.category, default: []].append(file)
        }

        let withinFileRule = SortRule(
            keys: rule.fileKeys ?? rule.keys,
            foldersFirst: false
        )
        let withinCmp = makeComparator(rule: withinFileRule)

        let orderedCategories = buckets.keys.sorted { a, b in
            let maxA = buckets[a]!.map(\.dateAdded).max() ?? .distantPast
            let maxB = buckets[b]!.map(\.dateAdded).max() ?? .distantPast
            if maxA != maxB {
                return maxA > maxB // bloque más reciente primero
            }
            return a.sortIndex < b.sortIndex
        }

        var sortedFiles: [FileEntry] = []
        for category in orderedCategories {
            let group = buckets[category]!.sorted(by: withinCmp)
            sortedFiles.append(contentsOf: group)
        }

        if rule.foldersFirst {
            return sortedFolders + sortedFiles
        }
        return sortedFiles + sortedFolders
    }

    public static func makeComparator(rule: SortRule) -> (FileEntry, FileEntry) -> Bool {
        { lhs, rhs in
            if rule.foldersFirst, lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

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

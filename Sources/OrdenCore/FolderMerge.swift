import Foundation

/// Diff previo a fusionar/mover una carpeta sobre otra con el mismo nombre.
public enum FolderMerge {
    public enum ItemKind: String, Sendable {
        case onlySource
        case onlyDest
        case identical
        case different
    }

    public struct DiffItem: Equatable, Sendable, Identifiable {
        public var id: String { relativePath }
        public let relativePath: String
        public let kind: ItemKind
        public let sourceSize: Int64?
        public let destSize: Int64?

        public init(relativePath: String, kind: ItemKind, sourceSize: Int64?, destSize: Int64?) {
            self.relativePath = relativePath
            self.kind = kind
            self.sourceSize = sourceSize
            self.destSize = destSize
        }
    }

    public struct Preview: Equatable, Sendable, Identifiable {
        public var id: String { sourcePath + "→" + destPath }
        public let sourcePath: String
        public let destPath: String
        public let items: [DiffItem]
        public var onlySourceCount: Int { items.filter { $0.kind == .onlySource }.count }
        public var conflictCount: Int { items.filter { $0.kind == .different }.count }
        public var identicalCount: Int { items.filter { $0.kind == .identical }.count }

        public init(sourcePath: String, destPath: String, items: [DiffItem]) {
            self.sourcePath = sourcePath
            self.destPath = destPath
            self.items = items
        }
    }

    public static func preview(source: String, dest: String, maxItems: Int = 500) -> Preview {
        let srcRoot = URL(fileURLWithPath: source)
        let dstRoot = URL(fileURLWithPath: dest)
        var srcMap: [String: Int64] = [:]
        var dstMap: [String: Int64] = [:]

        enumerate(root: srcRoot, into: &srcMap, max: maxItems)
        enumerate(root: dstRoot, into: &dstMap, max: maxItems)

        let keys = Set(srcMap.keys).union(dstMap.keys).sorted()
        var items: [DiffItem] = []
        for key in keys.prefix(maxItems) {
            let s = srcMap[key]
            let d = dstMap[key]
            let kind: ItemKind
            if s != nil, d == nil { kind = .onlySource }
            else if s == nil, d != nil { kind = .onlyDest }
            else if s == d { kind = .identical }
            else { kind = .different }
            items.append(DiffItem(relativePath: key, kind: kind, sourceSize: s, destSize: d))
        }
        return Preview(sourcePath: source, destPath: dest, items: items)
    }

    /// Copia lo nuevo al destino.
    /// - `overwriteConflicts == false`: los que chocan se guardan como «nombre 2».
    /// - `overwriteConflicts == true`: los que chocan se reemplazan por el archivo de origen.
    @discardableResult
    public static func mergeCopy(
        source: String,
        dest: String,
        overwriteConflicts: Bool = false
    ) throws -> [FileOps.TransferPair] {
        let preview = preview(source: source, dest: dest)
        var pairs: [FileOps.TransferPair] = []
        let fm = FileManager.default
        for item in preview.items where item.kind == .onlySource || item.kind == .different {
            let src = URL(fileURLWithPath: source).appendingPathComponent(item.relativePath)
            let parentRel = (item.relativePath as NSString).deletingLastPathComponent
            let destParent = parentRel.isEmpty
                ? URL(fileURLWithPath: dest)
                : URL(fileURLWithPath: dest).appendingPathComponent(parentRel)
            try fm.createDirectory(at: destParent, withIntermediateDirectories: true)

            if item.kind == .different, overwriteConflicts {
                let destFile = destParent.appendingPathComponent(src.lastPathComponent)
                if fm.fileExists(atPath: destFile.path) {
                    try fm.removeItem(at: destFile)
                }
                try fm.copyItem(at: src, to: destFile)
                pairs.append(FileOps.TransferPair(from: src.path, to: destFile.path))
            } else {
                let transferred = try FileOps.transfer(
                    paths: [src.path],
                    toDirectory: destParent.path,
                    move: false
                )
                pairs.append(contentsOf: transferred)
            }
        }
        return pairs
    }

    private static func enumerate(root: URL, into map: inout [String: Int64], max: Int) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        let rootPath = root.path
        while let url = enumerator.nextObject() as? URL {
            if map.count >= max { break }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            var rel = String(url.path.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            guard !rel.isEmpty else { continue }
            map[rel] = Int64(values?.fileSize ?? 0)
        }
    }
}

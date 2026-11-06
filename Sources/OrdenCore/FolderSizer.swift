import Foundation

/// Mide peso de archivos y carpetas (para UI y limpieza).
public enum FolderSizer {
    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Tamaño de un archivo o carpeta (recursivo, con tope de ítems).
    public static func measure(path: String, isDirectory: Bool, maxItems: Int = 80_000) -> Int64 {
        if !isDirectory {
            let vals = try? URL(fileURLWithPath: path)
                .resourceValues(forKeys: [.fileSizeKey])
            return Int64(vals?.fileSize ?? 0)
        }
        return recursiveDirectorySize(at: path, maxItems: maxItems)
    }

    public static func recursiveDirectorySize(at path: String, maxItems: Int = 80_000) -> Int64 {
        let root = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        var total: Int64 = 0
        var count = 0
        for case let url as URL in enumerator {
            count += 1
            if count > maxItems { break }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                continue
            }
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    /// Suma de tamaños ya medidos en la lista visible.
    public static func sum(_ entries: [FileEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.size }
    }
}

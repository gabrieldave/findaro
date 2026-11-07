import Foundation
import CryptoKit

/// SHA-256 de archivos y resumen ligero de árboles (conteo + bytes).
public enum FileDigest {
    public static func sha256File(at path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public struct TreeStats: Equatable, Sendable {
        public var fileCount: Int
        public var totalBytes: Int64

        public init(fileCount: Int, totalBytes: Int64) {
            self.fileCount = fileCount
            self.totalBytes = totalBytes
        }
    }

    /// Recorre el árbol (sigue el contenido real; no atraviesa symlinks de directorio).
    public static func treeStats(at path: String) throws -> TreeStats {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            throw FileOpsError.failed("No existe \(URL(fileURLWithPath: path).lastPathComponent)")
        }
        if !isDir.boolValue {
            let size = (try fm.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return TreeStats(fileCount: 1, totalBytes: size)
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return TreeStats(fileCount: 0, totalBytes: 0)
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            fileCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
        }
        return TreeStats(fileCount: fileCount, totalBytes: totalBytes)
    }
}

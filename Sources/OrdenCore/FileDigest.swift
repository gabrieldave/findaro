import Foundation
import CryptoKit

/// SHA-256 de archivos y manifiesto de integridad de árboles (incluye paquetes `.app`).
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

    public enum EntryKind: String, Equatable, Sendable {
        case file
        case symlink
    }

    /// Entrada relativa al raíz del árbol. Los symlinks no se dereferencian.
    public struct ManifestEntry: Equatable, Sendable, Comparable {
        public var relativePath: String
        public var kind: EntryKind
        public var sha256: String?
        public var symlinkTarget: String?
        public var byteSize: Int64

        public init(
            relativePath: String,
            kind: EntryKind,
            sha256: String? = nil,
            symlinkTarget: String? = nil,
            byteSize: Int64 = 0
        ) {
            self.relativePath = relativePath
            self.kind = kind
            self.sha256 = sha256
            self.symlinkTarget = symlinkTarget
            self.byteSize = byteSize
        }

        public static func < (lhs: ManifestEntry, rhs: ManifestEntry) -> Bool {
            lhs.relativePath < rhs.relativePath
        }

        public var fingerprintLine: String {
            switch kind {
            case .file:
                return "F|\(relativePath)|\(sha256 ?? "")|\(byteSize)"
            case .symlink:
                return "L|\(relativePath)|\(symlinkTarget ?? "")"
            }
        }
    }

    public struct TreeManifest: Equatable, Sendable {
        public var entries: [ManifestEntry]
        public var fileCount: Int
        public var totalBytes: Int64
        /// SHA-256 del manifiesto ordenado (no del contenido crudo).
        public var digest: String

        public var stats: TreeStats {
            TreeStats(fileCount: fileCount, totalBytes: totalBytes)
        }

        public init(entries: [ManifestEntry], fileCount: Int, totalBytes: Int64, digest: String) {
            self.entries = entries
            self.fileCount = fileCount
            self.totalBytes = totalBytes
            self.digest = digest
        }
    }

    /// Recorre el árbol. Incluye contenido de paquetes (`.app`, `.bundle`, …).
    /// Symlinks: se registran como enlace (destino textual); no se sigue el target.
    public static func treeManifest(at path: String) throws -> TreeManifest {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            throw FileOpsError.failed("No existe \(root.lastPathComponent)")
        }

        if !isDir.boolValue {
            let attrs = try fm.attributesOfItem(atPath: path)
            if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                let target = try fm.destinationOfSymbolicLink(atPath: path)
                let entry = ManifestEntry(
                    relativePath: root.lastPathComponent,
                    kind: .symlink,
                    symlinkTarget: target
                )
                return makeManifest(entries: [entry])
            }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let hash = try sha256File(at: path)
            let entry = ManifestEntry(
                relativePath: root.lastPathComponent,
                kind: .file,
                sha256: hash,
                byteSize: size
            )
            return makeManifest(entries: [entry])
        }

        var entries: [ManifestEntry] = []
        // No usar skipsPackageDescendants: los .app deben verificar su interior.
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isDirectoryKey,
                .fileSizeKey
            ],
            options: []
        ) else {
            return makeManifest(entries: [])
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey
            ])
            let rel = relativePath(of: url, under: root)
            guard !rel.isEmpty else { continue }

            if values.isSymbolicLink == true {
                let target = try fm.destinationOfSymbolicLink(atPath: url.path)
                entries.append(ManifestEntry(
                    relativePath: rel,
                    kind: .symlink,
                    symlinkTarget: target
                ))
                // No descendemos dentro de symlinks de directorio.
                enumerator.skipDescendants()
                continue
            }

            if values.isDirectory == true {
                continue
            }

            guard values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            let hash = try sha256File(at: url.path)
            entries.append(ManifestEntry(
                relativePath: rel,
                kind: .file,
                sha256: hash,
                byteSize: size
            ))
        }

        return makeManifest(entries: entries)
    }

    public static func treeStats(at path: String) throws -> TreeStats {
        try treeManifest(at: path).stats
    }

    public static func verifyManifest(_ expected: TreeManifest, at path: String) throws {
        let got = try treeManifest(at: path)
        if got.digest != expected.digest {
            throw FileOpsError.failed(
                "Manifiesto de integridad distinto (\(got.fileCount) archivos / \(got.totalBytes) B ≠ \(expected.fileCount)/\(expected.totalBytes))"
            )
        }
        if got.entries != expected.entries {
            throw FileOpsError.failed("Contenido del destino no coincide con el manifiesto SHA-256")
        }
    }

    private static func makeManifest(entries: [ManifestEntry]) -> TreeManifest {
        let sorted = entries.sorted()
        var fileCount = 0
        var totalBytes: Int64 = 0
        var fingerprint = ""
        for e in sorted {
            fingerprint += e.fingerprintLine + "\n"
            if e.kind == .file {
                fileCount += 1
                totalBytes += e.byteSize
            }
        }
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return TreeManifest(
            entries: sorted,
            fileCount: fileCount,
            totalBytes: totalBytes,
            digest: digest
        )
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(rootPath) else { return url.lastPathComponent }
        var rel = String(full.dropFirst(rootPath.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }
}

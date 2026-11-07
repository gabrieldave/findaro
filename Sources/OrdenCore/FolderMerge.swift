import Foundation
import CryptoKit

/// Diff previo a fusionar carpetas. Solo permite fusionar cuando la comparación está completa.
public enum FolderMerge {
    public enum ItemKind: String, Equatable, Sendable { case onlySource, onlyDest, identical, different }
    public enum MergeError: Error, LocalizedError {
        case incompletePreview(String), verificationFailed(String), unsupportedConflict(String), sourceChanged(String)
        public var errorDescription: String? {
            switch self {
            case .incompletePreview(let reason): return "No se puede fusionar con seguridad: \(reason)"
            case .verificationFailed(let path): return "No se pudo verificar la copia: \(path)"
            case .unsupportedConflict(let path): return "Conflicto entre archivo y carpeta: \(path)"
            case .sourceChanged(let path): return "El archivo de origen cambió durante la fusión: \(path)"
            }
        }
    }
    public struct DiffItem: Equatable, Sendable, Identifiable {
        public var id: String { relativePath }
        public let relativePath: String
        public let kind: ItemKind
        public let sourceSize: Int64?
        public let destSize: Int64?
        public let sourceIsDirectory: Bool
        public let sourceDigest: String?
        public init(relativePath: String, kind: ItemKind, sourceSize: Int64?, destSize: Int64?,
                    sourceIsDirectory: Bool = false, sourceDigest: String? = nil) {
            self.relativePath = relativePath; self.kind = kind
            self.sourceSize = sourceSize; self.destSize = destSize
            self.sourceIsDirectory = sourceIsDirectory; self.sourceDigest = sourceDigest
        }
    }
    public struct Preview: Equatable, Sendable, Identifiable {
        public var id: String { sourcePath + "→" + destPath }
        public let sourcePath: String
        public let destPath: String
        public let items: [DiffItem]
        public let isComplete: Bool
        public let hasTypeConflicts: Bool
        public let warnings: [String]
        public var onlySourceCount: Int { items.filter { $0.kind == .onlySource }.count }
        public var conflictCount: Int { items.filter { $0.kind == .different }.count }
        public var identicalCount: Int { items.filter { $0.kind == .identical }.count }
        public var canMerge: Bool { isComplete && !hasTypeConflicts }
        public init(sourcePath: String, destPath: String, items: [DiffItem], isComplete: Bool = true,
                    hasTypeConflicts: Bool = false, warnings: [String] = []) {
            self.sourcePath = sourcePath; self.destPath = destPath; self.items = items
            self.isComplete = isComplete; self.hasTypeConflicts = hasTypeConflicts; self.warnings = warnings
        }
    }
    private struct Record { let isDirectory: Bool; let size: Int64; let digest: String? }
    private struct Enumeration { let records: [String: Record]; let complete: Bool; let warnings: [String] }

    /// Incluye archivos ocultos y carpetas vacías. Un recorrido incompleto bloquea la fusión.
    public static func preview(source: String, dest: String, maxItems: Int = 50_000) -> Preview {
        let srcPath = canonical(source), dstPath = canonical(dest)
        guard isDirectory(srcPath), isDirectory(dstPath) else {
            return Preview(sourcePath: srcPath, destPath: dstPath, items: [], isComplete: false,
                           warnings: ["El origen y el destino deben existir y ser carpetas."])
        }
        if isSameOrDescendant(srcPath, of: dstPath) || isSameOrDescendant(dstPath, of: srcPath) {
            return Preview(sourcePath: srcPath, destPath: dstPath, items: [], isComplete: false,
                           warnings: ["El origen y el destino no pueden ser iguales ni estar uno dentro del otro."])
        }
        let limit = max(1, maxItems)
        let src = enumerate(URL(fileURLWithPath: srcPath), limit: limit)
        let dst = enumerate(URL(fileURLWithPath: dstPath), limit: limit)
        let keys = Set(src.records.keys).union(dst.records.keys).sorted()
        var items: [DiffItem] = [], typeConflict = false
        for key in keys {
            let s = src.records[key], d = dst.records[key]
            let kind: ItemKind
            if let s, let d {
                if s.isDirectory != d.isDirectory { kind = .different; typeConflict = true }
                else if s.isDirectory { kind = .identical }
                else if s.size == d.size && s.digest == d.digest { kind = .identical }
                else { kind = .different }
            } else if s != nil { kind = .onlySource } else { kind = .onlyDest }
            items.append(DiffItem(relativePath: key, kind: kind,
                sourceSize: s.map { $0.isDirectory ? 0 : $0.size },
                destSize: d.map { $0.isDirectory ? 0 : $0.size },
                sourceIsDirectory: s?.isDirectory ?? false, sourceDigest: s?.digest))
        }
        var warnings = src.warnings + dst.warnings
        if typeConflict { warnings.append("Hay rutas donde un lado contiene un archivo y el otro una carpeta. Resuelve esos conflictos manualmente.") }
        return Preview(sourcePath: srcPath, destPath: dstPath, items: items,
                       isComplete: src.complete && dst.complete, hasTypeConflicts: typeConflict, warnings: warnings)
    }

    /// Copia lo nuevo y los conflictos. Nunca elimina el origen. Verifica cada archivo con SHA-256.
    @discardableResult
    public static func mergeCopy(source: String, dest: String, overwriteConflicts: Bool = false) throws -> [FileOps.TransferPair] {
        let diff = preview(source: source, dest: dest)
        guard diff.canMerge else { throw MergeError.incompletePreview(diff.warnings.first ?? "La comparación no está completa.") }
        let fm = FileManager.default
        let sourceRoot = URL(fileURLWithPath: diff.sourcePath, isDirectory: true)
        let destRoot = URL(fileURLWithPath: diff.destPath, isDirectory: true)
        var pairs: [FileOps.TransferPair] = []
        for item in diff.items where item.kind == .onlySource || item.kind == .different {
            let src = sourceRoot.appendingPathComponent(item.relativePath)
            let requested = destRoot.appendingPathComponent(item.relativePath)
            if item.sourceIsDirectory {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: requested.path, isDirectory: &isDir) {
                    guard isDir.boolValue else { throw MergeError.unsupportedConflict(item.relativePath) }
                } else { try fm.createDirectory(at: requested, withIntermediateDirectories: true) }
                continue
            }
            try fm.createDirectory(at: requested.deletingLastPathComponent(), withIntermediateDirectories: true)
            let target: URL
            if item.kind == .different && !overwriteConflicts {
                target = FileOps.uniqueURL(requested)
                guard target.path != requested.path || !fm.fileExists(atPath: requested.path) else {
                    throw MergeError.unsupportedConflict(item.relativePath)
                }
            } else { target = requested }
            let temp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).merge-\(UUID().uuidString).tmp")
            defer { if fm.fileExists(atPath: temp.path) { try? fm.removeItem(at: temp) } }
            let before = try digest(src)
            guard item.sourceDigest == nil || before == item.sourceDigest else { throw MergeError.sourceChanged(item.relativePath) }
            try fm.copyItem(at: src, to: temp)
            let copied = try digest(temp), after = try digest(src)
            guard copied == before && after == before else { throw MergeError.sourceChanged(item.relativePath) }
            if overwriteConflicts && fm.fileExists(atPath: target.path) {
                let backup = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).backup-\(UUID().uuidString)")
                try fm.moveItem(at: target, to: backup)
                do {
                    try fm.moveItem(at: temp, to: target)
                    try? fm.removeItem(at: backup)
                } catch {
                    if !fm.fileExists(atPath: target.path) && fm.fileExists(atPath: backup.path) { try? fm.moveItem(at: backup, to: target) }
                    throw error
                }
            } else { try fm.moveItem(at: temp, to: target) }
            pairs.append(.init(from: src.path, to: target.path))
        }
        for pair in pairs {
            guard try digest(URL(fileURLWithPath: pair.from)) == digest(URL(fileURLWithPath: pair.to)) else {
                throw MergeError.verificationFailed(URL(fileURLWithPath: pair.from).lastPathComponent)
            }
        }
        return pairs
    }

    private static func enumerate(_ root: URL, limit: Int) -> Enumeration {
        let fm = FileManager.default
        var records: [String: Record] = [:], warnings: [String] = [], truncated = false
        var rootIsDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &rootIsDir), rootIsDir.boolValue,
              let iterator = fm.enumerator(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [],
                errorHandler: { url, error in warnings.append("\(url.path): \(error.localizedDescription)"); return true }) else {
            return Enumeration(records: [:], complete: false, warnings: ["No se pudo recorrer \(root.path)."])
        }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        while let url = iterator.nextObject() as? URL {
            if records.count >= limit { truncated = true; break }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                if values.isSymbolicLink == true { warnings.append("Enlace simbólico no compatible: \(url.path)"); continue }
                let directory = values.isDirectory == true
                guard directory || values.isRegularFile == true else { warnings.append("Elemento especial no compatible: \(url.path)"); continue }
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(prefix) else { warnings.append("Ruta fuera de la carpeta: \(path)"); continue }
                let relative = String(path.dropFirst(prefix.count))
                guard !relative.isEmpty else { continue }
                records[relative] = directory ? Record(isDirectory: true, size: 0, digest: nil)
                    : Record(isDirectory: false, size: Int64(values.fileSize ?? 0), digest: try digest(url))
            } catch { warnings.append("\(url.path): \(error.localizedDescription)") }
        }
        if truncated { warnings.append("Se alcanzó el límite de \(limit) elementos; la vista previa está incompleta.") }
        return Enumeration(records: records, complete: warnings.isEmpty && !truncated, warnings: warnings)
    }

    private static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
    private static func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        if path == root { return true }
        return path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}

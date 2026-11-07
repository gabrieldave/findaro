import Foundation
import CryptoKit

/// Comparación y fusión conservadora de carpetas. Nunca borra el origen durante la copia.
public enum FolderMerge {
    public enum ItemKind: String, Equatable, Sendable {
        case onlySource
        case onlyDest
        case identical
        case different
    }

    public enum MergeError: Error, LocalizedError {
        case incompletePreview(String)
        case verificationFailed(String)
        case unsupportedConflict(String)
        case sourceChanged(String)
        case destinationChanged(String)
        case rollbackFailed(String)

        public var errorDescription: String? {
            switch self {
            case .incompletePreview(let reason):
                return "No se puede fusionar con seguridad: \(reason)"
            case .verificationFailed(let path):
                return "No se pudo verificar la copia: \(path)"
            case .unsupportedConflict(let path):
                return "Conflicto entre archivo y carpeta: \(path)"
            case .sourceChanged(let path):
                return "El origen cambió durante la fusión: \(path)"
            case .destinationChanged(let path):
                return "El destino cambió durante la fusión: \(path)"
            case .rollbackFailed(let reason):
                return "La fusión falló y la recuperación quedó incompleta: \(reason)"
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
        public let destIsDirectory: Bool
        public let sourceDigest: String?
        public let destDigest: String?

        public init(
            relativePath: String,
            kind: ItemKind,
            sourceSize: Int64?,
            destSize: Int64?,
            sourceIsDirectory: Bool = false,
            destIsDirectory: Bool = false,
            sourceDigest: String? = nil,
            destDigest: String? = nil
        ) {
            self.relativePath = relativePath
            self.kind = kind
            self.sourceSize = sourceSize
            self.destSize = destSize
            self.sourceIsDirectory = sourceIsDirectory
            self.destIsDirectory = destIsDirectory
            self.sourceDigest = sourceDigest
            self.destDigest = destDigest
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
        public let sourceFingerprint: String?
        public let destFingerprint: String?

        public var onlySourceCount: Int { items.filter { $0.kind == .onlySource }.count }
        public var conflictCount: Int { items.filter { $0.kind == .different }.count }
        public var identicalCount: Int { items.filter { $0.kind == .identical }.count }
        public var canMerge: Bool { isComplete && !hasTypeConflicts && sourceFingerprint != nil }

        public init(
            sourcePath: String,
            destPath: String,
            items: [DiffItem],
            isComplete: Bool,
            hasTypeConflicts: Bool,
            warnings: [String],
            sourceFingerprint: String?,
            destFingerprint: String?
        ) {
            self.sourcePath = sourcePath
            self.destPath = destPath
            self.items = items
            self.isComplete = isComplete
            self.hasTypeConflicts = hasTypeConflicts
            self.warnings = warnings
            self.sourceFingerprint = sourceFingerprint
            self.destFingerprint = destFingerprint
        }
    }

    public struct Replacement: Equatable, Sendable {
        /// Ruta original del archivo que fue reemplazado.
        public let originalPath: String
        /// Copia anterior en la Papelera o, si no se pudo mover allí, en un respaldo oculto.
        public let backupPath: String

        public init(originalPath: String, backupPath: String) {
            self.originalPath = originalPath
            self.backupPath = backupPath
        }
    }

    public struct VerifiedDestination: Equatable, Sendable {
        public let path: String
        public let isDirectory: Bool
        public let digest: String?

        public init(path: String, isDirectory: Bool, digest: String?) {
            self.path = path
            self.isDirectory = isDirectory
            self.digest = digest
        }
    }

    public struct MergeResult: Equatable, Sendable {
        public let sourcePath: String
        public let sourceFingerprint: String
        public let maxItems: Int
        public let pairs: [FileOps.TransferPair]
        public let replacements: [Replacement]
        public let verifiedDestinations: [VerifiedDestination]
        public let warnings: [String]

        public init(
            sourcePath: String,
            sourceFingerprint: String,
            maxItems: Int,
            pairs: [FileOps.TransferPair],
            replacements: [Replacement],
            verifiedDestinations: [VerifiedDestination],
            warnings: [String]
        ) {
            self.sourcePath = sourcePath
            self.sourceFingerprint = sourceFingerprint
            self.maxItems = maxItems
            self.pairs = pairs
            self.replacements = replacements
            self.verifiedDestinations = verifiedDestinations
            self.warnings = warnings
        }
    }

    private struct Record: Equatable {
        let isDirectory: Bool
        let size: Int64
        let digest: String?
    }

    private struct Enumeration {
        let records: [String: Record]
        let complete: Bool
        let warnings: [String]
        let fingerprint: String?
    }

    private final class WarningCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func append(_ value: String) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    public static let defaultMaxItems = 100_000

    /// Incluye archivos ocultos, paquetes y carpetas vacías. Si el recorrido no es completo,
    /// la vista previa queda bloqueada y no permite mover el origen a la Papelera.
    public static func preview(source: String, dest: String, maxItems: Int = defaultMaxItems) -> Preview {
        guard !isSymbolicLink(source), !isSymbolicLink(dest) else {
            let sourcePath = URL(fileURLWithPath: source).standardizedFileURL.path
            let destPath = URL(fileURLWithPath: dest).standardizedFileURL.path
            return Preview(
                sourcePath: sourcePath,
                destPath: destPath,
                items: [],
                isComplete: false,
                hasTypeConflicts: false,
                warnings: ["No se puede fusionar usando un enlace simbólico como carpeta raíz. Abre la carpeta real y vuelve a intentarlo."],
                sourceFingerprint: nil,
                destFingerprint: nil
            )
        }

        let sourcePath = canonicalPath(source)
        let destPath = canonicalPath(dest)

        guard isDirectory(sourcePath), isDirectory(destPath) else {
            return Preview(
                sourcePath: sourcePath,
                destPath: destPath,
                items: [],
                isComplete: false,
                hasTypeConflicts: false,
                warnings: ["El origen y el destino deben existir y ser carpetas."],
                sourceFingerprint: nil,
                destFingerprint: nil
            )
        }

        if isSameOrDescendant(sourcePath, of: destPath) || isSameOrDescendant(destPath, of: sourcePath) {
            return Preview(
                sourcePath: sourcePath,
                destPath: destPath,
                items: [],
                isComplete: false,
                hasTypeConflicts: false,
                warnings: ["El origen y el destino no pueden ser iguales ni estar uno dentro del otro."],
                sourceFingerprint: nil,
                destFingerprint: nil
            )
        }

        let limit = max(1, maxItems)
        let sourceEnumeration = enumerate(root: URL(fileURLWithPath: sourcePath, isDirectory: true), maxItems: limit)
        let destEnumeration = enumerate(root: URL(fileURLWithPath: destPath, isDirectory: true), maxItems: limit)
        let keys = Set(sourceEnumeration.records.keys).union(destEnumeration.records.keys).sorted()

        var items: [DiffItem] = []
        var hasTypeConflicts = false

        for key in keys {
            let sourceRecord = sourceEnumeration.records[key]
            let destRecord = destEnumeration.records[key]
            let kind: ItemKind

            if let sourceRecord, let destRecord {
                if sourceRecord.isDirectory != destRecord.isDirectory {
                    kind = .different
                    hasTypeConflicts = true
                } else if sourceRecord.isDirectory {
                    kind = .identical
                } else if sourceRecord.size == destRecord.size && sourceRecord.digest == destRecord.digest {
                    kind = .identical
                } else {
                    kind = .different
                }
            } else if sourceRecord != nil {
                kind = .onlySource
            } else {
                kind = .onlyDest
            }

            items.append(DiffItem(
                relativePath: key,
                kind: kind,
                sourceSize: sourceRecord.map { $0.isDirectory ? 0 : $0.size },
                destSize: destRecord.map { $0.isDirectory ? 0 : $0.size },
                sourceIsDirectory: sourceRecord?.isDirectory ?? false,
                destIsDirectory: destRecord?.isDirectory ?? false,
                sourceDigest: sourceRecord?.digest,
                destDigest: destRecord?.digest
            ))
        }

        var warnings = sourceEnumeration.warnings + destEnumeration.warnings
        if hasTypeConflicts {
            warnings.append("Hay rutas donde un lado contiene un archivo y el otro una carpeta. Resuelve esos conflictos manualmente.")
        }

        let complete = sourceEnumeration.complete && destEnumeration.complete
        return Preview(
            sourcePath: sourcePath,
            destPath: destPath,
            items: items,
            isComplete: complete,
            hasTypeConflicts: hasTypeConflicts,
            warnings: warnings,
            sourceFingerprint: complete ? sourceEnumeration.fingerprint : nil,
            destFingerprint: complete ? destEnumeration.fingerprint : nil
        )
    }

    /// Copia todos los elementos nuevos y conflictos. Los archivos se copian a temporales,
    /// se verifican con SHA-256 y se instalan solo después de pasar la validación.
    /// Si algo falla, intenta revertir todos los cambios de destino.
    @discardableResult
    public static func mergeCopy(
        source: String,
        dest: String,
        overwriteConflicts: Bool = false,
        maxItems: Int = defaultMaxItems
    ) throws -> MergeResult {
        let diff = preview(source: source, dest: dest, maxItems: maxItems)
        guard diff.canMerge, let expectedFingerprint = diff.sourceFingerprint else {
            throw MergeError.incompletePreview(diff.warnings.first ?? "La comparación no está completa.")
        }

        let fm = FileManager.default
        let sourceRoot = URL(fileURLWithPath: diff.sourcePath, isDirectory: true)
        let destRoot = URL(fileURLWithPath: diff.destPath, isDirectory: true)
        var pairs: [FileOps.TransferPair] = []
        var installedFiles: [URL] = []
        var createdDirectories: [URL] = []
        var stagedBackups: [Replacement] = []
        var verifiedDestinations: [VerifiedDestination] = []

        do {
            for item in diff.items where item.kind == .onlySource || item.kind == .different {
                let sourceURL = sourceRoot.appendingPathComponent(item.relativePath)
                let requestedURL = destRoot.appendingPathComponent(item.relativePath)

                guard fm.fileExists(atPath: sourceURL.path) else {
                    throw MergeError.sourceChanged(item.relativePath)
                }

                if item.sourceIsDirectory {
                    try ensureDirectory(at: requestedURL, createdDirectories: &createdDirectories)
                    verifiedDestinations.append(VerifiedDestination(path: requestedURL.path, isDirectory: true, digest: nil))
                    continue
                }

                try ensureDirectory(at: requestedURL.deletingLastPathComponent(), createdDirectories: &createdDirectories)

                let sourceDigest = try digestFile(sourceURL)
                guard sourceDigest == item.sourceDigest else {
                    throw MergeError.sourceChanged(item.relativePath)
                }

                var targetURL = requestedURL
                if item.kind == .different && overwriteConflicts {
                    var destinationIsDirectory: ObjCBool = false
                    if fm.fileExists(atPath: requestedURL.path, isDirectory: &destinationIsDirectory) {
                        guard !destinationIsDirectory.boolValue else {
                            throw MergeError.unsupportedConflict(item.relativePath)
                        }
                        guard let expectedDestinationDigest = item.destDigest,
                              try digestFile(requestedURL) == expectedDestinationDigest else {
                            throw MergeError.destinationChanged(item.relativePath)
                        }

                        let backupURL = requestedURL.deletingLastPathComponent()
                            .appendingPathComponent(".\(requestedURL.lastPathComponent).ordena-backup-\(UUID().uuidString)")
                        try fm.moveItem(at: requestedURL, to: backupURL)
                        guard try digestFile(backupURL) == expectedDestinationDigest else {
                            try? fm.moveItem(at: backupURL, to: requestedURL)
                            throw MergeError.destinationChanged(item.relativePath)
                        }
                        stagedBackups.append(Replacement(originalPath: requestedURL.path, backupPath: backupURL.path))
                    }
                } else if fm.fileExists(atPath: requestedURL.path) {
                    targetURL = FileOps.uniqueURL(requestedURL)
                }

                let temporaryURL = targetURL.deletingLastPathComponent()
                    .appendingPathComponent(".\(targetURL.lastPathComponent).ordena-merge-\(UUID().uuidString).tmp")

                do {
                    try fm.copyItem(at: sourceURL, to: temporaryURL)
                    let copiedDigest = try digestFile(temporaryURL)
                    let sourceDigestAfterCopy = try digestFile(sourceURL)
                    guard copiedDigest == sourceDigest && sourceDigestAfterCopy == sourceDigest else {
                        throw MergeError.sourceChanged(item.relativePath)
                    }
                    try fm.moveItem(at: temporaryURL, to: targetURL)
                    installedFiles.append(targetURL)
                    pairs.append(FileOps.TransferPair(from: sourceURL.path, to: targetURL.path))
                    verifiedDestinations.append(VerifiedDestination(path: targetURL.path, isDirectory: false, digest: sourceDigest))
                } catch {
                    if fm.fileExists(atPath: temporaryURL.path) {
                        try? fm.removeItem(at: temporaryURL)
                    }
                    throw error
                }
            }

            // Los elementos idénticos también deben seguir intactos en destino:
            // si alguien cambia o elimina uno durante la copia, no se puede retirar el origen.
            for item in diff.items where item.kind == .identical {
                let destinationURL = destRoot.appendingPathComponent(item.relativePath)
                if item.sourceIsDirectory {
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        throw MergeError.destinationChanged(item.relativePath)
                    }
                    verifiedDestinations.append(VerifiedDestination(path: destinationURL.path, isDirectory: true, digest: nil))
                } else {
                    guard let expectedDigest = item.sourceDigest,
                          fm.fileExists(atPath: destinationURL.path),
                          try digestFile(destinationURL) == expectedDigest else {
                        throw MergeError.destinationChanged(item.relativePath)
                    }
                    verifiedDestinations.append(VerifiedDestination(path: destinationURL.path, isDirectory: false, digest: expectedDigest))
                }
            }

            let sourceAfterCopy = enumerate(root: sourceRoot, maxItems: maxItems)
            guard sourceAfterCopy.complete, sourceAfterCopy.fingerprint == expectedFingerprint else {
                throw MergeError.sourceChanged(diff.sourcePath)
            }
            try verifyDestinations(verifiedDestinations)

            for pair in pairs {
                let originalDigest = try digestFile(URL(fileURLWithPath: pair.from))
                let copiedDigest = try digestFile(URL(fileURLWithPath: pair.to))
                guard originalDigest == copiedDigest else {
                    throw MergeError.verificationFailed(URL(fileURLWithPath: pair.from).lastPathComponent)
                }
            }

            // Los originales reemplazados se mandan a la Papelera para que sigan siendo recuperables.
            // Si macOS no permite mover alguno, se conserva el respaldo oculto en su carpeta.
            var replacements: [Replacement] = []
            var warnings: [String] = []
            for backup in stagedBackups {
                let backupURL = URL(fileURLWithPath: backup.backupPath)
                var trashedURL: NSURL?
                do {
                    try fm.trashItem(at: backupURL, resultingItemURL: &trashedURL)
                    replacements.append(Replacement(
                        originalPath: backup.originalPath,
                        backupPath: trashedURL?.path ?? backup.backupPath
                    ))
                } catch {
                    replacements.append(backup)
                    warnings.append("Se conservó un respaldo oculto de \(URL(fileURLWithPath: backup.originalPath).lastPathComponent): \(error.localizedDescription)")
                }
            }

            return MergeResult(
                sourcePath: diff.sourcePath,
                sourceFingerprint: expectedFingerprint,
                maxItems: maxItems,
                pairs: pairs,
                replacements: replacements,
                verifiedDestinations: verifiedDestinations,
                warnings: warnings
            )
        } catch {
            var rollbackErrors: [String] = []

            for file in installedFiles.reversed() {
                do {
                    if fm.fileExists(atPath: file.path) {
                        try fm.removeItem(at: file)
                    }
                } catch {
                    rollbackErrors.append("\(file.lastPathComponent): \(error.localizedDescription)")
                }
            }

            for backup in stagedBackups.reversed() {
                let backupURL = URL(fileURLWithPath: backup.backupPath)
                let originalURL = URL(fileURLWithPath: backup.originalPath)
                do {
                    if fm.fileExists(atPath: backupURL.path) {
                        guard !fm.fileExists(atPath: originalURL.path) else {
                            rollbackErrors.append("El destino ya existe y no se pudo restaurar \(originalURL.lastPathComponent)")
                            continue
                        }
                        try fm.moveItem(at: backupURL, to: originalURL)
                    }
                } catch {
                    rollbackErrors.append("\(backupURL.lastPathComponent): \(error.localizedDescription)")
                }
            }

            for directory in createdDirectories.reversed() {
                try? fm.removeItem(at: directory)
            }

            if !rollbackErrors.isEmpty {
                throw MergeError.rollbackFailed("\(error.localizedDescription). \(rollbackErrors.joined(separator: "; "))")
            }
            throw error
        }
    }

    /// Mueve el origen a la Papelera solo si sigue siendo exactamente el mismo árbol
    /// que se comparó y copió. Primero lo renombra en su mismo volumen y verifica de nuevo.
    @discardableResult
    public static func trashSourceAfterVerifiedMerge(_ result: MergeResult) throws -> String? {
        let fm = FileManager.default
        let sourceURL = URL(fileURLWithPath: result.sourcePath, isDirectory: true)
        let current = enumerate(root: sourceURL, maxItems: result.maxItems)
        guard current.complete, current.fingerprint == result.sourceFingerprint else {
            throw MergeError.sourceChanged(result.sourcePath)
        }
        try verifyDestinations(result.verifiedDestinations)

        let stagingURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".\(sourceURL.lastPathComponent).ordena-trash-\(UUID().uuidString)")
        try fm.moveItem(at: sourceURL, to: stagingURL)

        do {
            let staged = enumerate(root: stagingURL, maxItems: result.maxItems)
            guard staged.complete, staged.fingerprint == result.sourceFingerprint else {
                throw MergeError.sourceChanged(result.sourcePath)
            }
            // Vuelve a verificar destino después de mover el origen a staging y justo antes de Papelera.
            try verifyDestinations(result.verifiedDestinations)

            var trashedURL: NSURL?
            try fm.trashItem(at: stagingURL, resultingItemURL: &trashedURL)
            return trashedURL?.path
        } catch {
            if fm.fileExists(atPath: stagingURL.path), !fm.fileExists(atPath: sourceURL.path) {
                do {
                    try fm.moveItem(at: stagingURL, to: sourceURL)
                } catch {
                    throw MergeError.rollbackFailed(
                        "\(error.localizedDescription). El origen quedó en \(stagingURL.path)"
                    )
                }
            }
            throw error
        }
    }

    private static func verifyDestinations(_ checks: [VerifiedDestination]) throws {
        let fm = FileManager.default
        for check in checks {
            if check.isDirectory {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: check.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw MergeError.destinationChanged(URL(fileURLWithPath: check.path).lastPathComponent)
                }
            } else {
                guard let expected = check.digest,
                      fm.fileExists(atPath: check.path),
                      try digestFile(URL(fileURLWithPath: check.path)) == expected else {
                    throw MergeError.destinationChanged(URL(fileURLWithPath: check.path).lastPathComponent)
                }
            }
        }
    }

    private static func isSymbolicLink(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
    }

    private static func ensureDirectory(at url: URL, createdDirectories: inout [URL]) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw MergeError.unsupportedConflict(url.lastPathComponent)
            }
            return
        }

        var missing: [URL] = []
        var cursor = url
        while !fm.fileExists(atPath: cursor.path) {
            missing.append(cursor)
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else {
                throw MergeError.unsupportedConflict(url.path)
            }
            cursor = parent
        }

        var parentIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: cursor.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            throw MergeError.unsupportedConflict(cursor.path)
        }

        for directory in missing.reversed() {
            try fm.createDirectory(at: directory, withIntermediateDirectories: false)
            createdDirectories.append(directory)
        }
    }

    private static func enumerate(root: URL, maxItems: Int) -> Enumeration {
        let fm = FileManager.default
        let warnings = WarningCollector()
        var records: [String: Record] = [:]
        var truncated = false
        var rootIsDirectory: ObjCBool = false

        guard fm.fileExists(atPath: root.path, isDirectory: &rootIsDirectory),
              rootIsDirectory.boolValue,
              let iterator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [],
                errorHandler: { url, error in
                    warnings.append("\(url.path): \(error.localizedDescription)")
                    return true
                }
              ) else {
            return Enumeration(
                records: [:],
                complete: false,
                warnings: ["No se pudo recorrer \(root.path)."],
                fingerprint: nil
            )
        }

        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"

        while let url = iterator.nextObject() as? URL {
            if records.count >= maxItems {
                truncated = true
                break
            }

            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                if values.isSymbolicLink == true {
                    warnings.append("Enlace simbólico no compatible: \(url.path)")
                    iterator.skipDescendants()
                    continue
                }

                let isDirectory = values.isDirectory == true
                guard isDirectory || values.isRegularFile == true else {
                    warnings.append("Elemento especial no compatible: \(url.path)")
                    continue
                }

                let itemPath = url.standardizedFileURL.path
                guard itemPath.hasPrefix(prefix) else {
                    warnings.append("Ruta fuera de la carpeta: \(itemPath)")
                    continue
                }

                let relativePath = String(itemPath.dropFirst(prefix.count))
                guard !relativePath.isEmpty else { continue }

                if isDirectory {
                    records[relativePath] = Record(isDirectory: true, size: 0, digest: nil)
                } else {
                    records[relativePath] = Record(
                        isDirectory: false,
                        size: Int64(values.fileSize ?? 0),
                        digest: try digestFile(url)
                    )
                }
            } catch {
                warnings.append("\(url.path): \(error.localizedDescription)")
            }
        }

        if truncated {
            warnings.append("Se alcanzó el límite de \(maxItems) elementos; la vista previa está incompleta.")
        }

        let warningList = warnings.snapshot()
        let complete = warningList.isEmpty && !truncated
        return Enumeration(
            records: records,
            complete: complete,
            warnings: warningList,
            fingerprint: complete ? fingerprint(records) : nil
        )
    }

    private static func fingerprint(_ records: [String: Record]) -> String {
        var hasher = SHA256()
        for (path, record) in records.sorted(by: { $0.key < $1.key }) {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data((record.isDirectory ? "D" : "F").utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(String(record.size).utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data((record.digest ?? "").utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func digestFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        let resolvedPath = canonicalPath(path)
        let resolvedRoot = canonicalPath(root)
        if resolvedPath == resolvedRoot { return true }
        let prefix = resolvedRoot == "/" ? "/" : resolvedRoot + "/"
        return resolvedPath.hasPrefix(prefix)
    }
}

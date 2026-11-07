import Foundation

public enum FileOpsError: Error, LocalizedError {
    case destinationExists(String)
    case sameFolder
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let name): return "Ya existe: \(name)"
        case .sameFolder: return "Origen y destino son la misma carpeta"
        case .failed(let msg): return msg
        }
    }
}

public enum FileOps {
    /// Qué hará la bandeja al soltar en una carpeta.
    public enum ShelfIntent: String, Codable, Sendable, Hashable {
        case copy
        case move
    }

    public struct ShelfItem: Equatable, Identifiable, Sendable, Codable, Hashable {
        public var id: String { path }
        public let path: String
        public let name: String
        public var intent: ShelfIntent

        public init(path: String, name: String, intent: ShelfIntent = .move) {
            self.path = path
            self.name = name
            self.intent = intent
        }

        public init(entry: FileEntry, intent: ShelfIntent = .move) {
            self.path = entry.path
            self.name = entry.name
            self.intent = intent
        }
    }

    /// Par origen → destino tras transferir (para deshacer).
    public struct TransferPair: Equatable, Sendable {
        public let from: String
        public let to: String
        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// Copia o mueve rutas a una carpeta destino. Si falla una operación,
    /// intenta revertir las operaciones anteriores para evitar transferencias parciales.
    @discardableResult
    public static func transfer(paths: [String], toDirectory destinationDir: String, move: Bool) throws -> [TransferPair] {
        let fm = FileManager.default
        let destinationURL = URL(fileURLWithPath: destinationDir).standardizedFileURL.resolvingSymlinksInPath()
        var destinationIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destinationURL.path, isDirectory: &destinationIsDirectory),
              destinationIsDirectory.boolValue else { throw FileOpsError.failed("Destino no es carpeta") }

        var seen = Set<String>()
        let uniquePaths = paths.filter { seen.insert(URL(fileURLWithPath: $0).standardizedFileURL.path).inserted }
        for path in uniquePaths {
            let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
            guard fm.fileExists(atPath: sourceURL.path) else {
                throw FileOpsError.failed("No existe el origen: \(sourceURL.lastPathComponent)")
            }
            if sourceURL.resolvingSymlinksInPath().path == destinationURL.path { throw FileOpsError.sameFolder }
            var sourceIsDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: sourceURL.path, isDirectory: &sourceIsDirectory)
            if sourceIsDirectory.boolValue,
               isSameOrDescendant(destinationURL.path, of: sourceURL.resolvingSymlinksInPath().path) {
                throw FileOpsError.sameFolder
            }
        }

        var pairs: [TransferPair] = []
        do {
            for path in uniquePaths {
                let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
                if sourceURL.deletingLastPathComponent().resolvingSymlinksInPath().path == destinationURL.path { continue }
                let destination = uniqueURL(destinationURL.appendingPathComponent(sourceURL.lastPathComponent))
                do {
                    if move { try fm.moveItem(at: sourceURL, to: destination) }
                    else { try fm.copyItem(at: sourceURL, to: destination) }
                    pairs.append(TransferPair(from: sourceURL.path, to: destination.path))
                } catch {
                    if !move, fm.fileExists(atPath: destination.path) { try? fm.removeItem(at: destination) }
                    if move, !fm.fileExists(atPath: sourceURL.path), fm.fileExists(atPath: destination.path) {
                        pairs.append(TransferPair(from: sourceURL.path, to: destination.path))
                    }
                    throw error
                }
            }
        } catch {
            let originalError = error.localizedDescription
            var rollbackErrors: [String] = []
            for pair in pairs.reversed() {
                let current = URL(fileURLWithPath: pair.to)
                let original = URL(fileURLWithPath: pair.from)
                do {
                    if move {
                        guard fm.fileExists(atPath: current.path) else { continue }
                        guard !fm.fileExists(atPath: original.path) else {
                            rollbackErrors.append("El origen ya existe: \(original.lastPathComponent)")
                            continue
                        }
                        try fm.moveItem(at: current, to: original)
                    } else if fm.fileExists(atPath: current.path) {
                        try fm.removeItem(at: current)
                    }
                } catch {
                    rollbackErrors.append("\(current.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if rollbackErrors.isEmpty {
                throw FileOpsError.failed("La transferencia falló y se revirtieron los cambios: \(originalError)")
            }
            throw FileOpsError.failed("La transferencia falló: \(originalError). Errores al revertir: \(rollbackErrors.joined(separator: "; "))")
        }
        return pairs
    }

    private static func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        if path == root { return true }
        return path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// Crea una carpeta dentro de `parent`. Si el nombre existe, añade " 2", " 3"…
    @discardableResult
    public static func createFolder(named name: String, in parent: String) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw FileOpsError.failed("Nombre vacío") }
        let fm = FileManager.default
        var dest = URL(fileURLWithPath: parent).appendingPathComponent(cleaned)
        dest = uniqueURL(dest)
        try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        return dest.path
    }

    /// Crea un archivo vacío (o con texto) dentro de `parent`. Si el nombre existe, añade " 2", " 3"…
    @discardableResult
    public static func createFile(
        named name: String,
        in parent: String,
        contents: String = ""
    ) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw FileOpsError.failed("Nombre vacío") }
        if cleaned.contains("/") || cleaned == ".." || cleaned == "." {
            throw FileOpsError.failed("Nombre inválido")
        }
        let fm = FileManager.default
        var dest = URL(fileURLWithPath: parent).appendingPathComponent(cleaned)
        dest = uniqueURL(dest)
        let data = Data(contents.utf8)
        guard fm.createFile(atPath: dest.path, contents: data, attributes: nil) else {
            throw FileOpsError.failed("No se pudo crear el archivo")
        }
        return dest.path
    }

    /// Renombra un archivo/carpeta (mismo directorio padre).
    @discardableResult
    public static func rename(path: String, to newName: String) throws -> String {
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw FileOpsError.failed("Nombre vacío") }
        if cleaned.contains("/") || cleaned == ".." || cleaned == "." {
            throw FileOpsError.failed("Nombre inválido")
        }
        let fm = FileManager.default
        let src = URL(fileURLWithPath: path)
        let dest = src.deletingLastPathComponent().appendingPathComponent(cleaned)
        if src.path == dest.path { return path }
        if fm.fileExists(atPath: dest.path) {
            throw FileOpsError.destinationExists(cleaned)
        }
        try fm.moveItem(at: src, to: dest)
        return dest.path
    }

    /// Duplica un ítem en el mismo directorio (`archivo copia.ext` / `carpeta copia`).
    @discardableResult
    public static func duplicate(path: String) throws -> String {
        let fm = FileManager.default
        let src = URL(fileURLWithPath: path)
        let parent = src.deletingLastPathComponent()
        let base = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        let copyName = ext.isEmpty ? "\(base) copia" : "\(base) copia.\(ext)"
        var dest = parent.appendingPathComponent(copyName)
        dest = uniqueURL(dest)
        try fm.copyItem(at: src, to: dest)
        return dest.path
    }

    public static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        for i in 2...999 {
            let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return url
    }
}

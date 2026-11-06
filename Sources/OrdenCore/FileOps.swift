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

    /// Copia o mueve rutas a una carpeta destino. Devuelve los pares realizados.
    @discardableResult
    public static func transfer(
        paths: [String],
        toDirectory destinationDir: String,
        move: Bool
    ) throws -> [TransferPair] {
        let fm = FileManager.default
        var destIsDir: ObjCBool = false
        guard fm.fileExists(atPath: destinationDir, isDirectory: &destIsDir), destIsDir.boolValue else {
            throw FileOpsError.failed("Destino no es carpeta")
        }

        var pairs: [TransferPair] = []
        for path in paths {
            let src = URL(fileURLWithPath: path)
            let parent = src.deletingLastPathComponent().path
            if (parent as NSString).standardizingPath == (destinationDir as NSString).standardizingPath {
                continue
            }
            var dest = URL(fileURLWithPath: destinationDir)
                .appendingPathComponent(src.lastPathComponent)
            dest = uniqueURL(dest)
            do {
                if move {
                    try fm.moveItem(at: src, to: dest)
                } else {
                    try fm.copyItem(at: src, to: dest)
                }
                pairs.append(TransferPair(from: path, to: dest.path))
            } catch {
                throw FileOpsError.failed(error.localizedDescription)
            }
        }
        return pairs
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

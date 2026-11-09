import Foundation

public enum FileOpsError: Error, LocalizedError {
    case destinationExists(String)
    case sameFolder
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let name): return "Ya existe: \(name)"
        case .sameFolder: return "Origen y destino son la misma carpeta o el destino está dentro del origen"
        case .failed(let msg): return msg
        }
    }
}

public enum FileOps {
    public enum ShelfIntent: String, Codable, Sendable, Hashable { case copy, move }

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

    public struct TransferPair: Equatable, Sendable {
        public let from: String
        public let to: String
        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// Valida todo el lote antes de modificar el disco. Si una operación falla,
    /// elimina las copias parciales e intenta revertir los movimientos ya realizados.
    @discardableResult
    public static func transfer(paths: [String], toDirectory destinationDir: String, move: Bool) throws -> [TransferPair] {
        try LicenseGate.requireWrite()
        let fm = FileManager.default
        let destinationURL = URL(fileURLWithPath: destinationDir)
            .standardizedFileURL.resolvingSymlinksInPath()
        var destinationIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destinationURL.path, isDirectory: &destinationIsDirectory),
              destinationIsDirectory.boolValue else {
            throw FileOpsError.failed("El destino no existe o no es una carpeta")
        }

        var seen = Set<String>()
        var sources: [(url: URL, resolvedPath: String, isDirectory: Bool)] = []

        for rawPath in paths {
            let cleaned = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let sourceURL = URL(fileURLWithPath: cleaned).standardizedFileURL
            let resolvedPath = sourceURL.resolvingSymlinksInPath().path
            guard seen.insert(resolvedPath).inserted else { continue }

            guard fm.fileExists(atPath: sourceURL.path) else {
                throw FileOpsError.failed("No existe el origen: \(sourceURL.lastPathComponent)")
            }

            if resolvedPath == destinationURL.path {
                throw FileOpsError.sameFolder
            }

            var sourceIsDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: sourceURL.path, isDirectory: &sourceIsDirectory)
            if sourceIsDirectory.boolValue,
               isSameOrDescendant(destinationURL.path, of: resolvedPath) {
                throw FileOpsError.sameFolder
            }

            let sourceParent = sourceURL.deletingLastPathComponent()
                .resolvingSymlinksInPath().path
            if sourceParent == destinationURL.path {
                continue
            }

            sources.append((sourceURL, resolvedPath, sourceIsDirectory.boolValue))
        }

        guard !sources.isEmpty else { return [] }

        var completed: [TransferPair] = []
        do {
            for source in sources {
                let destination = uniqueURL(destinationURL.appendingPathComponent(source.url.lastPathComponent))
                let temporary = destinationURL.appendingPathComponent(".ordena-transfer-\(UUID().uuidString)")

                do {
                    if move {
                        try fm.moveItem(at: source.url, to: temporary)
                    } else {
                        try fm.copyItem(at: source.url, to: temporary)
                    }

                    try fm.moveItem(at: temporary, to: destination)
                    completed.append(TransferPair(from: source.url.path, to: destination.path))
                } catch {
                    // FileManager puede dejar un temporal si falla una copia/movimiento
                    // entre volúmenes. No dejamos restos ni perdemos el origen.
                    if fm.fileExists(atPath: temporary.path) {
                        if move && !fm.fileExists(atPath: source.url.path) {
                            do {
                                try fm.moveItem(at: temporary, to: source.url)
                            } catch {
                                throw FileOpsError.failed(
                                    "Falló la transferencia y no pude devolver \(source.url.lastPathComponent) a su origen: \(error.localizedDescription)"
                                )
                            }
                        } else {
                            try? fm.removeItem(at: temporary)
                        }
                    } else if fm.fileExists(atPath: destination.path) {
                        // Si el temporal desapareció y el origen también, el movimiento
                        // pudo terminar justo antes de reportarse el error: incluirlo en rollback.
                        if move && !fm.fileExists(atPath: source.url.path) {
                            completed.append(TransferPair(from: source.url.path, to: destination.path))
                        } else if !move {
                            // El destino se eligió libre antes de comenzar este lote.
                            try? fm.removeItem(at: destination)
                        }
                    }
                    throw error
                }
            }
        } catch {
            let originalError = error.localizedDescription
            var rollbackErrors: [String] = []

            for pair in completed.reversed() {
                let current = URL(fileURLWithPath: pair.to)
                let original = URL(fileURLWithPath: pair.from)
                do {
                    guard fm.fileExists(atPath: current.path) else { continue }
                    if move {
                        guard !fm.fileExists(atPath: original.path) else {
                            rollbackErrors.append("El origen ya existe: \(original.lastPathComponent)")
                            continue
                        }
                        try fm.moveItem(at: current, to: original)
                    } else {
                        try fm.removeItem(at: current)
                    }
                } catch {
                    rollbackErrors.append("\(current.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if rollbackErrors.isEmpty {
                throw FileOpsError.failed("La transferencia falló y se revirtieron los cambios: \(originalError)")
            }
            throw FileOpsError.failed(
                "La transferencia falló: \(originalError). No se pudo revertir: \(rollbackErrors.joined(separator: "; "))"
            )
        }

        return completed
    }

    private static func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedRoot = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path
        if resolvedPath == resolvedRoot { return true }
        let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        return resolvedPath.hasPrefix(prefix)
    }

    private static func validatedName(_ name: String) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              cleaned != ".",
              cleaned != "..",
              !cleaned.contains("/"),
              !cleaned.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw FileOpsError.failed("Nombre inválido: usa un solo nombre de archivo o carpeta")
        }
        return cleaned
    }

    @discardableResult
    public static func createFolder(named name: String, in parent: String) throws -> String {
        try LicenseGate.requireWrite()
        let cleaned = try validatedName(name)
        let fm = FileManager.default
        var parentIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: parent, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            throw FileOpsError.failed("La carpeta contenedora no existe")
        }
        let destination = uniqueURL(URL(fileURLWithPath: parent).appendingPathComponent(cleaned))
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination.path
    }

    @discardableResult
    public static func createFile(named name: String, in parent: String, contents: String = "") throws -> String {
        try LicenseGate.requireWrite()
        let cleaned = try validatedName(name)
        let fm = FileManager.default
        var parentIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: parent, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            throw FileOpsError.failed("La carpeta contenedora no existe")
        }
        let destination = uniqueURL(URL(fileURLWithPath: parent).appendingPathComponent(cleaned))
        guard fm.createFile(atPath: destination.path, contents: Data(contents.utf8), attributes: nil) else {
            throw FileOpsError.failed("No se pudo crear el archivo")
        }
        return destination.path
    }

    @discardableResult
    public static func rename(path: String, to newName: String) throws -> String {
        try LicenseGate.requireWrite()
        let cleaned = try validatedName(newName)
        let fm = FileManager.default
        let source = URL(fileURLWithPath: path).standardizedFileURL
        guard fm.fileExists(atPath: source.path) else {
            throw FileOpsError.failed("No existe el elemento que quieres renombrar")
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(cleaned)
        if source.path == destination.path { return path }
        if fm.fileExists(atPath: destination.path) {
            throw FileOpsError.destinationExists(cleaned)
        }
        try fm.moveItem(at: source, to: destination)
        return destination.path
    }

    @discardableResult
    public static func duplicate(path: String) throws -> String {
        try LicenseGate.requireWrite()
        let fm = FileManager.default
        let source = URL(fileURLWithPath: path).standardizedFileURL
        guard fm.fileExists(atPath: source.path) else {
            throw FileOpsError.failed("No existe el elemento que quieres duplicar")
        }
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        let copyName = ext.isEmpty ? "\(base) copia" : "\(base) copia.\(ext)"
        let destination = uniqueURL(source.deletingLastPathComponent().appendingPathComponent(copyName))
        try fm.copyItem(at: source, to: destination)
        return destination.path
    }

    public static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let directory = url.deletingLastPathComponent()
        for index in 2...999 {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        // No devuelve una ruta libre; la operación posterior fallará sin sobrescribir.
        return url
    }
}

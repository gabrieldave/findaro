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
    public struct ShelfItem: Equatable, Identifiable, Sendable, Codable, Hashable {
        public var id: String { path }
        public let path: String
        public let name: String

        public init(path: String, name: String) {
            self.path = path
            self.name = name
        }

        public init(entry: FileEntry) {
            self.path = entry.path
            self.name = entry.name
        }
    }

    /// Copia o mueve rutas a una carpeta destino. Devuelve cuántos se procesaron.
    @discardableResult
    public static func transfer(
        paths: [String],
        toDirectory destinationDir: String,
        move: Bool
    ) throws -> Int {
        let fm = FileManager.default
        var destIsDir: ObjCBool = false
        guard fm.fileExists(atPath: destinationDir, isDirectory: &destIsDir), destIsDir.boolValue else {
            throw FileOpsError.failed("Destino no es carpeta")
        }

        var count = 0
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
                count += 1
            } catch {
                throw FileOpsError.failed(error.localizedDescription)
            }
        }
        return count
    }

    private static func uniqueURL(_ url: URL) -> URL {
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

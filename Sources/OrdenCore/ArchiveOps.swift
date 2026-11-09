import Foundation

/// Descompresión local (sin Utilidad de Archivos / Finder).
public enum ArchiveOps {
    public enum Error: Swift.Error, LocalizedError {
        case unsupported(String)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupported(let name): return "No sé descomprimir «\(name)» aquí"
            case .failed(let msg): return msg
            }
        }
    }

    /// Formatos que Findaro puede expandir sin salir a otra app.
    public static func isExtractable(_ path: String) -> Bool {
        extractKind(for: path) != nil
    }

    public static func archiveStem(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let lower = name.lowercased()
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz"] {
            if lower.hasSuffix(suffix) {
                return String(name.dropLast(suffix.count))
            }
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Extrae junto al archivo. Devuelve la carpeta o el ítem principal resultante.
    public static func extract(archivePath: String) throws -> String {
        try LicenseGate.requireWrite()
        let fm = FileManager.default
        guard fm.fileExists(atPath: archivePath) else {
            throw Error.failed("No existe el archivo")
        }
        guard let kind = extractKind(for: archivePath) else {
            throw Error.unsupported(URL(fileURLWithPath: archivePath).lastPathComponent)
        }

        let parent = (archivePath as NSString).deletingLastPathComponent
        let stagingName = ".findaro-extract-\(UUID().uuidString)"
        let staging = (parent as NSString).appendingPathComponent(stagingName)
        try fm.createDirectory(atPath: staging, withIntermediateDirectories: true)

        do {
            try runExtract(kind: kind, archivePath: archivePath, into: staging)
            let result = try settleExtractedContents(from: staging, parent: parent, preferredStem: archiveStem(for: archivePath))
            try? fm.removeItem(atPath: staging)
            return result
        } catch {
            try? fm.removeItem(atPath: staging)
            throw error
        }
    }

    // MARK: - Private

    private enum Kind {
        case zip
        case tar
    }

    private static func extractKind(for path: String) -> Kind? {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tar.xz") || name.hasSuffix(".tgz") {
            return .tar
        }
        let ext = (name as NSString).pathExtension
        switch ext {
        case "zip": return .zip
        case "tar", "gz", "bz2", "xz":
            // .gz/.bz2/.xz sueltos (no tar.*): dejar al sistema; tar -xf a veces falla.
            if ext == "tar" { return .tar }
            return nil
        default:
            return nil
        }
    }

    private static func runExtract(kind: Kind, archivePath: String, into staging: String) throws {
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: staging)
        switch kind {
        case .zip:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archivePath, staging]
        case .tar:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", archivePath, "-C", staging]
        }
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw Error.failed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.failed(msg?.isEmpty == false ? msg! : "Falló la descompresión")
        }
    }

    private static func settleExtractedContents(from staging: String, parent: String, preferredStem: String) throws -> String {
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(atPath: staging)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        guard !children.isEmpty else {
            throw Error.failed("El archivo estaba vacío")
        }

        if children.count == 1 {
            let only = children[0]
            let from = (staging as NSString).appendingPathComponent(only)
            let dest = uniquePath(in: parent, name: only)
            try fm.moveItem(atPath: from, toPath: dest)
            return dest
        }

        let folderName = uniquePath(in: parent, name: preferredStem)
        try fm.createDirectory(atPath: folderName, withIntermediateDirectories: true)
        for child in children {
            let from = (staging as NSString).appendingPathComponent(child)
            let to = (folderName as NSString).appendingPathComponent(child)
            try fm.moveItem(atPath: from, toPath: to)
        }
        return folderName
    }

    private static func uniquePath(in parent: String, name: String) -> String {
        let fm = FileManager.default
        var candidate = (parent as NSString).appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate) { return candidate }
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension
        var n = 2
        while true {
            let labeled = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = (parent as NSString).appendingPathComponent(labeled)
            if !fm.fileExists(atPath: candidate) { return candidate }
            n += 1
        }
    }
}

import Foundation
import UniformTypeIdentifiers

/// Papelera del usuario y utilidades (ruta canónica + vaciado + fallback a Finder para saltar restricciones de TCC).
public enum TrashOps {
    /// Ruta real de la Papelera del usuario (`~/.Trash` o la que macOS exponga).
    public static var userTrashPath: String {
        if let url = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            return (url.path as NSString).standardizingPath
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ((home as NSString).appendingPathComponent(".Trash") as NSString).standardizingPath
    }

    public static func isTrashPath(_ path: String) -> Bool {
        let a = (path as NSString).standardizingPath
        let b = userTrashPath
        if a == b { return true }
        // Comparar también por resolución de symlink.
        let ra = URL(fileURLWithPath: a).resolvingSymlinksInPath().path
        let rb = URL(fileURLWithPath: b).resolvingSymlinksInPath().path
        if ra == rb { return true }
        // Comprobar si termina en /.Trash o similar
        return a.hasSuffix("/.Trash") || ra.hasSuffix("/.Trash")
    }

    /// ¿El error parece denegación de acceso a la Papelera / disco completo?
    public static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return true }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) || ns.code == Int(EACCES) { return true }
        let text = error.localizedDescription.lowercased()
        return text.contains("autoriz")
            || text.contains("permission")
            || text.contains("no tienes")
            || text.contains("not permitted")
            || text.contains("couldn't be opened")
            || text.contains("no se ha podido abrir")
    }

    /// Carga todos los ítems de la papelera a través de AppleScript / Finder.
    /// Finder ya tiene permisos nativos del sistema y evita el bloqueo TCC (EPERM / Acceso total al disco).
    public static func loadTrashViaFinder() -> [FileEntry] {
        let script = """
        set outList to {}
        tell application "Finder"
            repeat with i from 1 to (count of items of trash)
                set end of outList to POSIX path of (item i of trash as text)
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return outList as text
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(decoding: data, as: UTF8.self)
            let paths = raw.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let fm = FileManager.default
            let keys: [URLResourceKey] = [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey,
                .addedToDirectoryDateKey,
                .localizedTypeDescriptionKey
            ]

            return paths.compactMap { itemPath in
                let url = URL(fileURLWithPath: itemPath)
                let name = url.lastPathComponent
                var isDir: ObjCBool = false
                fm.fileExists(atPath: itemPath, isDirectory: &isDir)
                let isDirectory = isDir.boolValue

                let values = try? url.resourceValues(forKeys: Set(keys))
                let attrs = (try? fm.attributesOfItem(atPath: itemPath)) ?? [:]

                let size = Int64(values?.fileSize ?? (attrs[.size] as? Int ?? 0))
                let modified = values?.contentModificationDate
                    ?? (attrs[.modificationDate] as? Date)
                    ?? Date()
                let created = values?.creationDate
                    ?? (attrs[.creationDate] as? Date)
                    ?? modified
                let added = values?.addedToDirectoryDate ?? created
                let kind = values?.localizedTypeDescription
                    ?? UTType(filenameExtension: url.pathExtension)?.localizedDescription
                    ?? (isDirectory ? "Carpeta" : "Documento")

                return FileEntry(
                    path: itemPath,
                    name: name,
                    isDirectory: isDirectory,
                    size: size,
                    dateModified: modified,
                    dateCreated: created,
                    dateAdded: added,
                    kind: kind
                )
            }
        } catch {
            return []
        }
    }

    /// Mueve un archivo fuera de la Papelera usando Finder (evita errores de permisos en macOS).
    public static func moveViaFinder(source: String, destDir: String) throws -> String {
        let script = """
        tell application "Finder"
            move (POSIX file "\(source)") to (POSIX file "\(destDir)" as alias)
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let err = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "TrashOps", code: Int(p.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: err.isEmpty ? "Finder falló al mover el archivo" : err
            ])
        }
        let fileName = URL(fileURLWithPath: source).lastPathComponent
        return (destDir as NSString).appendingPathComponent(fileName)
    }

    /// Elimina definitivamente un archivo mediante Finder si FileManager arroja permiso denegado.
    public static func deleteViaFinder(path: String) -> Bool {
        let script = """
        tell application "Finder"
            delete (POSIX file "\(path)")
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Vacía la papelera directamente con Finder (nunca falla por TCC).
    public static func emptyTrashViaFinder() -> Bool {
        let script = """
        tell application "Finder"
            empty trash
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Borra permanentemente rutas (ya están en la Papelera o confirmado).
    public static func permanentlyDelete(paths: [String]) throws -> (ok: Int, failures: [String]) {
        try LicenseGate.requireWrite()
        let fm = FileManager.default
        var ok = 0
        var failures: [String] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            do {
                try fm.removeItem(at: url)
                ok += 1
            } catch {
                if deleteViaFinder(path: path) {
                    ok += 1
                } else {
                    failures.append("\(name): \(error.localizedDescription)")
                }
            }
        }
        return (ok, failures)
    }

    /// Vacía la Papelera del usuario listando y borrando (con fallback a Finder).
    public static func emptyUserTrash() throws -> (ok: Int, failures: [String]) {
        try LicenseGate.requireWrite()
        let path = userTrashPath
        do {
            let entries = try DirectoryLoader.load(path: path, includeHidden: true)
            return try permanentlyDelete(paths: entries.map(\.path))
        } catch {
            if emptyTrashViaFinder() {
                return (1, [])
            }
            throw error
        }
    }
}

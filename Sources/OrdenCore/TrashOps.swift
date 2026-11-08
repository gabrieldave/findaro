import Foundation

/// Papelera del usuario y utilidades (ruta canónica + vaciado).
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
        return ra == rb
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

    /// Borra permanentemente rutas (ya están en la Papelera o confirmado).
    public static func permanentlyDelete(paths: [String]) throws -> (ok: Int, failures: [String]) {
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
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return (ok, failures)
    }

    /// Vacía la Papelera del usuario listando y borrando.
    public static func emptyUserTrash() throws -> (ok: Int, failures: [String]) {
        let path = userTrashPath
        let entries = try DirectoryLoader.load(path: path, includeHidden: true)
        return try permanentlyDelete(paths: entries.map(\.path))
    }
}

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
        if ns.domain == NSCocoaErrorDomain,
           ns.code == NSFileReadNoPermissionError || ns.code == NSFileWriteNoPermissionError { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == Int(EPERM) || underlying.code == Int(EACCES) { return true }
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
        let r = runOSAScript(script)
        guard r.status == 0 else { return [] }
        let raw = r.stdout
        do {
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
        }
    }

    // MARK: - AppleScript seguro (sin interpolar rutas en el código)

    /// Ejecuta un AppleScript con `osascript`, pasando las rutas como argumentos (`on run argv`).
    /// Nunca se interpola un nombre de archivo dentro del código del script: un archivo llamado
    /// `x" & (do shell script "…") & "` no puede inyectar órdenes.
    @discardableResult
    static func runOSAScript(_ source: String, arguments: [String] = []) -> (status: Int32, stdout: String, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source] + arguments
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        // Leer ANTES de esperar: con miles de ítems la salida supera el búfer del pipe (64 KB)
        // y `waitUntilExit()` se quedaba colgado para siempre.
        final class Box: @unchecked Sendable { var data = Data() } // escrito antes de signal(), leído después de wait()
        let errBox = Box()
        let errHandle = err.fileHandleForReading
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            errBox.data = errHandle.readDataToEndOfFile()
            errDone.signal()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        errDone.wait()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errBox.data, as: UTF8.self))
    }

    /// ¿macOS denegó el control de Finder (Ajustes → Privacidad → Automatización)?
    /// errAEEventNotPermitted = -1743.
    public static func isAutomationDenied(_ stderr: String) -> Bool {
        stderr.contains("-1743") || stderr.lowercased().contains("not authorized to send apple events")
    }

    /// Mueve un archivo fuera de la Papelera usando Finder (evita errores de permisos en macOS).
    public static func moveViaFinder(source: String, destDir: String) throws -> String {
        let script = """
        on run argv
            set src to POSIX file (item 1 of argv)
            set dst to POSIX file (item 2 of argv) as alias
            tell application "Finder" to move src to dst
        end run
        """
        let r = runOSAScript(script, arguments: [source, destDir])
        if r.status != 0 {
            throw NSError(domain: "TrashOps", code: Int(r.status), userInfo: [
                NSLocalizedDescriptionKey: r.stderr.isEmpty ? "Finder falló al mover el archivo" : r.stderr
            ])
        }
        let fileName = URL(fileURLWithPath: source).lastPathComponent
        return (destDir as NSString).appendingPathComponent(fileName)
    }

    public enum EmptyTrashOutcome: Sendable, Equatable {
        /// Finder vació la Papelera (una sola orden, un solo permiso).
        case emptiedByFinder
        /// Borrado directo con FileManager (requiere Acceso completo al disco).
        case deletedDirectly(ok: Int, failures: [String])
        /// macOS no deja a Findaro controlar Finder ni leer la Papelera.
        case needsPermission(message: String)
    }

    /// Vacía la papelera con UNA sola orden a Finder.
    /// Antes se lanzaba un `osascript` por cada archivo, lo que disparaba un aviso de permisos
    /// por elemento ("me pidió 10 mil permisos") y además no borraba nada: `delete` de Finder
    /// sobre un ítem que ya está en la Papelera no lo elimina.
    public static func emptyTrashViaFinder() -> (ok: Bool, automationDenied: Bool, error: String) {
        let script = """
        with timeout of 3600 seconds
            tell application "Finder"
                if (count of items of trash) > 0 then
                    empty trash
                end if
            end tell
        end timeout
        """
        let r = runOSAScript(script)
        return (r.status == 0, isAutomationDenied(r.stderr), r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Prepara un ítem para poder borrarlo: quita el candado (uchg) y da permiso de escritura al dueño,
    /// también dentro de carpetas (p. ej. cachés de Go/npm con carpetas de solo lectura).
    static func unlockForDeletion(_ url: URL) {
        let fm = FileManager.default
        func unlock(_ u: URL) {
            // Carpetas: el dueño necesita escribir (borrar hijos) y entrar (x) para recorrerlas.
            try? fm.setAttributes([.immutable: false], ofItemAtPath: u.path)
            if let current = (try? fm.attributesOfItem(atPath: u.path))?[.posixPermissions] as? NSNumber {
                try? fm.setAttributes([.posixPermissions: NSNumber(value: current.uint16Value | 0o700)], ofItemAtPath: u.path)
            }
        }
        unlock(url)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        if let walker = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in true }) {
            for case let child as URL in walker {
                var childIsDir: ObjCBool = false
                if fm.fileExists(atPath: child.path, isDirectory: &childIsDir), childIsDir.boolValue {
                    unlock(child)
                } else {
                    // Solo el candado; los permisos del archivo no impiden borrarlo si la carpeta es escribible.
                    try? fm.setAttributes([.immutable: false], ofItemAtPath: child.path)
                }
            }
        }
    }

    /// Borra permanentemente rutas (ya están en la Papelera o confirmado).
    /// Solo FileManager: sin un `osascript` por archivo (eso generaba cientos de avisos de permisos).
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
            } catch let firstError {
                // Reintento tras quitar candados / solo-lectura.
                unlockForDeletion(url)
                do {
                    try fm.removeItem(at: url)
                    ok += 1
                } catch {
                    let reason = isPermissionError(firstError)
                        ? "macOS bloqueó el acceso (activa Acceso completo al disco para Findaro o usa «Vaciar Papelera»)"
                        : firstError.localizedDescription
                    failures.append("\(name): \(reason)")
                }
            }
        }
        return (ok, failures)
    }

    /// Vacía la Papelera del usuario.
    /// 1) Una sola orden a Finder (`empty trash`): no requiere Acceso completo al disco y
    ///    macOS pregunta UNA vez («Findaro quiere controlar Finder»).
    /// 2) Si Automatización está denegada, borrado directo (solo funciona con Acceso completo al disco).
    /// 3) Si ambas fallan, devuelve `.needsPermission` con instrucciones claras (sin bucles de avisos).
    public static func emptyTrash() throws -> EmptyTrashOutcome {
        try LicenseGate.requireWrite()
        let finder = emptyTrashViaFinder()
        if finder.ok { return .emptiedByFinder }

        // Lectura directa: si no hay Acceso completo al disco, esto lanza EPERM (no usamos Finder aquí).
        let fm = FileManager.default
        let trashURL = URL(fileURLWithPath: userTrashPath)
        if let items = try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: []) {
            let result = try permanentlyDelete(paths: items.map(\.path))
            return .deletedDirectly(ok: result.ok, failures: result.failures)
        }

        let message: String
        if finder.automationDenied {
            message = "macOS no permite que Findaro controle Finder. Ve a Ajustes del Sistema → Privacidad y seguridad → Automatización → Findaro y activa «Finder», o activa Acceso completo al disco para Findaro."
        } else {
            message = finder.error.isEmpty
                ? "No se pudo vaciar la Papelera. Activa Acceso completo al disco para Findaro y vuelve a intentarlo."
                : "No se pudo vaciar la Papelera: \(finder.error)"
        }
        return .needsPermission(message: message)
    }

    /// Compatibilidad: API anterior usada por tests y código existente.
    public static func emptyUserTrash() throws -> (ok: Int, failures: [String]) {
        switch try emptyTrash() {
        case .emptiedByFinder:
            return (1, [])
        case .deletedDirectly(let ok, let failures):
            return (ok, failures)
        case .needsPermission(let message):
            throw NSError(domain: "TrashOps", code: Int(EPERM), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

import AppKit
import OrdenCore

/// Panel tipo Finder → Obtener información (versión ligera).
@MainActor
enum FileInfoPanel {
    static func show(_ entry: FileEntry) {
        let url = URL(fileURLWithPath: entry.path)
        let attrs = (try? FileManager.default.attributesOfItem(atPath: entry.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? entry.size
        let created = attrs[.creationDate] as? Date ?? entry.dateCreated
        let modified = attrs[.modificationDate] as? Date ?? entry.dateModified
        let posix = attrs[.posixPermissions] as? NSNumber

        let sizeText: String = {
            if entry.isDirectory {
                return FolderSizer.format(entry.size > 0 ? entry.size : size)
            }
            return FolderSizer.format(size)
        }()

        let permText: String = {
            guard let posix else { return "—" }
            let v = posix.uint16Value
            return String(format: "%o", v & 0o777)
        }()

        let df = DateFormatter()
        df.locale = Locale(identifier: "es_MX")
        df.dateStyle = .medium
        df.timeStyle = .medium

        let kind = entry.isDirectory ? "Carpeta" : entry.category.labelSpanish
        let lines = [
            "Nombre: \(entry.name)",
            "Tipo: \(kind)",
            "Tamaño: \(sizeText)",
            "Agregado: \(df.string(from: entry.dateAdded))",
            "Modificado: \(df.string(from: modified))",
            "Creado: \(df.string(from: created))",
            "Permisos: \(permText)",
            "",
            "Ubicación:",
            url.deletingLastPathComponent().path,
            "",
            entry.path
        ]

        let alert = NSAlert()
        alert.messageText = "Información"
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        let icon = NSWorkspace.shared.icon(forFile: entry.path)
        icon.size = NSSize(width: 64, height: 64)
        alert.icon = icon
        alert.addButton(withTitle: "Listo")
        alert.addButton(withTitle: "Mostrar en Finder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

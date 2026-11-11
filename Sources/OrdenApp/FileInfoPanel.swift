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
        df.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "es_MX")
        df.dateStyle = .medium
        df.timeStyle = .medium

        let kind = entry.isDirectory ? L10n.s("Carpeta", "Folder") : entry.category.labelLocalized
        let lines = [
            "\(L10n.s("Nombre", "Name")): \(entry.name)",
            "\(L10n.s("Tipo", "Type")): \(kind)",
            "\(L10n.s("Tamaño", "Size")): \(sizeText)",
            "\(L10n.s("Agregado", "Date Added")): \(df.string(from: entry.dateAdded))",
            "\(L10n.s("Modificado", "Modified")): \(df.string(from: modified))",
            "\(L10n.s("Creado", "Created")): \(df.string(from: created))",
            "\(L10n.s("Permisos", "Permissions")): \(permText)",
            "",
            "\(L10n.s("Ubicación", "Location")):",
            url.deletingLastPathComponent().path,
            "",
            entry.path
        ]

        let alert = NSAlert()
        alert.messageText = L10n.s("Información", "Information")
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        let icon = NSWorkspace.shared.icon(forFile: entry.path)
        icon.size = NSSize(width: 64, height: 64)
        alert.icon = icon
        alert.addButton(withTitle: L10n.s("Listo", "Done"))
        let finderTitle = DefaultFileViewerManager.isEnabled
            ? L10n.s("Abrir carpeta en Finder", "Open folder in Finder")
            : L10n.s("Mostrar en Finder", "Show in Finder")
        alert.addButton(withTitle: finderTitle)
        if FindaroAlert.runModal(alert) == .alertSecondButtonReturn {
            if DefaultFileViewerManager.isEnabled {
                let folderURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
                let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
                NSWorkspace.shared.open([folderURL], withApplicationAt: finderURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}

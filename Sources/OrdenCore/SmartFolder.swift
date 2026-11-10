import Foundation

/// Carpeta inteligente: una búsqueda guardada que vive en Favoritos.
/// Al abrirla se muestran solo los archivos que cumplen sus reglas
/// (tipo, extensión, nombre, fecha), en su carpeta y, si se pide, en sus subcarpetas.
/// Nunca mueve ni copia archivos: es solo una vista.
public struct SmartFolder: Identifiable, Codable, Equatable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    /// Carpeta donde busca.
    public var rootPath: String
    /// `true` = también dentro de las subcarpetas.
    public var includeSubfolders: Bool
    /// Tipos (Imagen, PDF…). Vacío + sin extensiones = cualquier tipo.
    public var categories: [FileCategory]
    /// Extensiones sin punto, en minúsculas (`zip`, `rar`). Se suman a `categories` (O).
    public var extensions: [String]
    /// Texto que debe contener el nombre (vacío = cualquiera).
    public var nameContains: String
    /// Fecha de agregado/descarga (o creación). `nil` = cualquier fecha.
    public var dateWindow: ShortcutDateWindow?
    public var createdAt: Date

    public static let maxCount = 60

    public init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        includeSubfolders: Bool = false,
        categories: [FileCategory] = [],
        extensions: [String] = [],
        nameContains: String = "",
        dateWindow: ShortcutDateWindow? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.includeSubfolders = includeSubfolders
        self.categories = categories
        self.extensions = SmartFolder.normalizeExtensions(extensions)
        self.nameContains = nameContains
        self.dateWindow = dateWindow
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, rootPath, includeSubfolders, categories, extensions, nameContains, dateWindow, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        rootPath = try c.decodeIfPresent(String.self, forKey: .rootPath) ?? NSHomeDirectory()
        includeSubfolders = try c.decodeIfPresent(Bool.self, forKey: .includeSubfolders) ?? false
        categories = try c.decodeIfPresent([FileCategory].self, forKey: .categories) ?? []
        extensions = SmartFolder.normalizeExtensions(
            try c.decodeIfPresent([String].self, forKey: .extensions) ?? []
        )
        nameContains = try c.decodeIfPresent(String.self, forKey: .nameContains) ?? ""
        dateWindow = try c.decodeIfPresent(ShortcutDateWindow.self, forKey: .dateWindow)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    // MARK: - Reglas

    /// Hay al menos una regla (si no, sería «todo»).
    public var hasCriteria: Bool {
        !categories.isEmpty
            || !extensions.isEmpty
            || !trimmedName.isEmpty
            || dateWindow != nil
    }

    private var trimmedName: String {
        nameContains
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasTypeCriteria: Bool {
        !categories.isEmpty || !extensions.isEmpty
    }

    /// ¿Este archivo entra en la carpeta inteligente?
    /// Tipo (categoría O extensión) Y nombre Y fecha.
    public func matches(_ entry: FileEntry, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if entry.isDirectory {
            // Carpetas solo cuando no se pide un tipo concreto y se mira un único nivel
            // (p. ej. «descargado hoy» en Descargas incluye una carpeta descargada hoy).
            if hasTypeCriteria || includeSubfolders { return false }
        } else if hasTypeCriteria {
            let ext = (entry.name as NSString).pathExtension.lowercased()
            let byExtension = !ext.isEmpty && extensions.contains(ext)
            let byCategory = !categories.isEmpty && categories.contains(entry.category)
            if !byExtension && !byCategory { return false }
        }

        let needle = trimmedName
        if !needle.isEmpty, !entry.name.localizedCaseInsensitiveContains(needle) {
            return false
        }

        if let window = dateWindow {
            let hit = window.matches(entry.dateAdded, now: now, calendar: calendar)
                || window.matches(entry.dateCreated, now: now, calendar: calendar)
            if !hit { return false }
        }
        return true
    }

    // MARK: - Utilidades

    /// `".ZIP, rar  7z;*.tar.gz"` → `["zip", "rar", "7z", "gz"]` (sin duplicados, en orden).
    public static func parseExtensions(_ raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",; \n\t")
        return normalizeExtensions(raw.components(separatedBy: separators))
    }

    public static func normalizeExtensions(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in list {
            var token = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            token = token.replacingOccurrences(of: "*", with: "")
            // «tar.gz» / «.zip» → última extensión real, como la ve el sistema.
            if let dot = token.lastIndex(of: ".") {
                token = String(token[token.index(after: dot)...])
            }
            token = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !token.isEmpty, token.count <= 12, !seen.contains(token) else { continue }
            seen.insert(token)
            out.append(token)
        }
        return out
    }

    /// Traduce lo escrito en el buscador a reglas: «*.pdf» / «pdf» → extensión, «imágenes» → tipo,
    /// cualquier otra cosa → «el nombre contiene».
    public static func criteria(fromSearchText raw: String) -> (categories: [FileCategory], extensions: [String], nameContains: String) {
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return ([], [], "") }
        let stripped = typed.replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = stripped.lowercased()
        let isSingleToken = !lower.isEmpty && !lower.contains(" ")

        if isSingleToken, lower.hasPrefix(".") {
            let exts = parseExtensions(lower)
            if !exts.isEmpty { return ([], exts, "") }
        }
        if isSingleToken {
            let folded = lower.folding(options: .diacriticInsensitive, locale: nil)
            let words: [String: FileCategory] = [
                "imagen": .image, "imagenes": .image, "image": .image, "images": .image,
                "foto": .image, "fotos": .image, "photo": .image, "photos": .image,
                "video": .video, "videos": .video, "pelicula": .video, "peliculas": .video, "movies": .video,
                "musica": .audio, "music": .audio, "audio": .audio, "audios": .audio, "canciones": .audio,
                "comprimido": .archive, "comprimidos": .archive, "archives": .archive,
                "word": .word, "excel": .excel, "powerpoint": .powerpoint
            ]
            if let category = words[folded] {
                return ([category], [], "")
            }
            if folded == "documentos" || folded == "documents" {
                return (AssistantShortcut.documentCategories, [], "")
            }
            // «pdf», «zip», «mp4», «dmg»… = extensión conocida.
            if lower.count <= 5,
               lower.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }),
               FileCategory.classify(fileName: "x.\(lower)", isDirectory: false) != .other {
                return ([], [lower], "")
            }
        }
        return ([], [], typed)
    }

    public var extensionsText: String {
        extensions.joined(separator: ", ")
    }

    /// Icono SF Symbol según la regla principal.
    public var symbolName: String {
        if categories.count == 1, let only = categories.first {
            return only.symbolName
        }
        if categories.isEmpty, !extensions.isEmpty {
            let cats = Set(extensions.map { FileCategory.classify(fileName: "x.\($0)", isDirectory: false) })
            if cats.count == 1, let only = cats.first, only != .other {
                return only.symbolName
            }
        }
        if !hasTypeCriteria, dateWindow != nil {
            return "clock.arrow.circlepath"
        }
        return "folder.badge.gearshape"
    }

    /// Color del icono (mismo tinte que el tipo de archivo).
    public var tintHex: String {
        if categories.count == 1, let only = categories.first {
            return only.tintHex
        }
        if categories.isEmpty, !extensions.isEmpty {
            let cats = Set(extensions.map { FileCategory.classify(fileName: "x.\($0)", isDirectory: false) })
            if cats.count == 1, let only = cats.first, only != .other {
                return only.tintHex
            }
        }
        return "8B9CFF"
    }

    /// Resumen legible: «PDF · .zip · “factura” · hoy · Descargas y subcarpetas».
    public var summaryLocalized: String {
        var parts: [String] = []
        if !categories.isEmpty {
            parts.append(categories.map(\.labelLocalized).joined(separator: ", "))
        }
        if !extensions.isEmpty {
            parts.append(extensions.map { ".\($0)" }.joined(separator: " "))
        }
        if !hasTypeCriteria {
            parts.append(L10n.s("Todos los tipos", "All types"))
        }
        let needle = trimmedName
        if !needle.isEmpty {
            parts.append(L10n.s("nombre con «\(needle)»", "name contains “\(needle)”"))
        }
        if let window = dateWindow {
            parts.append(L10n.s("agregado \(window.labelSpanish)", "added \(window.labelEnglish)"))
        }
        let folder = URL(fileURLWithPath: rootPath).lastPathComponent
        let place = includeSubfolders
            ? L10n.s("en \(folder) y subcarpetas", "in \(folder) and subfolders")
            : L10n.s("en \(folder)", "in \(folder)")
        parts.append(place)
        return parts.joined(separator: " · ")
    }

    /// Nombre sugerido según las reglas (cuando el usuario no escribió uno).
    public var suggestedName: String {
        var base: String
        if categories.count == 1, let only = categories.first {
            base = only.organizeFolderNameLocalized
        } else if categories.isEmpty, extensions.count == 1, let ext = extensions.first {
            base = L10n.s("Archivos .\(ext)", ".\(ext) files")
        } else if !hasTypeCriteria {
            base = L10n.s("Archivos", "Files")
        } else {
            base = L10n.s("Búsqueda", "Search")
        }
        let needle = trimmedName
        if !needle.isEmpty {
            base += " «\(needle)»"
        }
        if let window = dateWindow {
            base += L10n.s(" de \(window.labelSpanish)", " · \(window.labelEnglish)")
        }
        return base
    }

    // MARK: - Plantillas rápidas (la hoja de creación las ofrece en un clic)

    public enum Preset: String, CaseIterable, Sendable {
        case images, pdf, downloadedToday, archives, videos, documents, audio

        public var titleLocalized: String {
            switch self {
            case .images: return L10n.s("Imágenes", "Images")
            case .pdf: return "PDF"
            case .downloadedToday: return L10n.s("Descargado hoy", "Downloaded today")
            case .archives: return L10n.s("ZIP y comprimidos", "ZIP & archives")
            case .videos: return L10n.s("Videos", "Videos")
            case .documents: return L10n.s("Documentos", "Documents")
            case .audio: return L10n.s("Música y audio", "Music & audio")
            }
        }

        public var symbolName: String {
            switch self {
            case .images: return FileCategory.image.symbolName
            case .pdf: return FileCategory.pdf.symbolName
            case .downloadedToday: return "arrow.down.circle"
            case .archives: return FileCategory.archive.symbolName
            case .videos: return FileCategory.video.symbolName
            case .documents: return "doc.on.doc"
            case .audio: return FileCategory.audio.symbolName
            }
        }

        /// Aplica la plantilla sobre un borrador (conserva id y carpeta si no hace falta cambiarla).
        public func apply(to draft: SmartFolder, homePath: String = NSHomeDirectory()) -> SmartFolder {
            var next = draft
            next.extensions = []
            next.nameContains = ""
            next.dateWindow = nil
            switch self {
            case .images:
                next.categories = [.image]
            case .pdf:
                next.categories = [.pdf]
            case .downloadedToday:
                next.categories = []
                next.dateWindow = .today
                next.rootPath = (homePath as NSString).appendingPathComponent("Downloads")
                next.includeSubfolders = false
            case .archives:
                next.categories = [.archive]
            case .videos:
                next.categories = [.video]
            case .documents:
                next.categories = AssistantShortcut.documentCategories
            case .audio:
                next.categories = [.audio]
            }
            next.name = titleLocalized
            return next
        }
    }
}

// MARK: - Búsqueda en subcarpetas

public enum SmartFolderSearch {
    /// Recorre `root` (y subcarpetas si la carpeta inteligente lo pide) y devuelve solo las coincidencias.
    /// No sigue enlaces simbólicos ni entra en paquetes (.app, .photoslibrary…).
    /// Topes para no congelar el Mac en carpetas enormes.
    public static func collect(
        folder: SmartFolder,
        root: String,
        includeHidden: Bool = false,
        maxResults: Int = 5_000,
        maxDepth: Int = 12,
        maxVisited: Int = 400_000,
        now: Date = Date(),
        isCancelled: () -> Bool = { false }
    ) -> (entries: [FileEntry], truncated: Bool) {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .addedToDirectoryDateKey, .localizedTypeDescriptionKey,
            .isHiddenKey, .isSymbolicLinkKey, .isPackageKey
        ]
        let keySet = Set(keys)
        var results: [FileEntry] = []
        var visited = 0
        var truncated = false
        var stack: [(url: URL, depth: Int)] = [(rootURL, 0)]
        let calendar = Calendar.current

        while let current = stack.popLast() {
            if isCancelled() { break }
            guard let children = try? fm.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: keys,
                options: includeHidden ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for child in children {
                visited += 1
                if visited >= maxVisited || results.count >= maxResults {
                    truncated = true
                    break
                }
                guard let values = try? child.resourceValues(forKeys: keySet) else { continue }
                if !includeHidden, values.isHidden == true { continue }
                if values.isSymbolicLink == true { continue }

                let isDirectory = values.isDirectory == true
                let isPackage = values.isPackage == true
                let entry = makeEntry(child, values: values, isDirectory: isDirectory && !isPackage)
                if folder.matches(entry, now: now, calendar: calendar) {
                    results.append(entry)
                }
                if isDirectory, !isPackage, folder.includeSubfolders, current.depth < maxDepth {
                    stack.append((child, current.depth + 1))
                }
            }
            if truncated { break }
        }
        return (results, truncated)
    }

    private static func makeEntry(_ url: URL, values: URLResourceValues, isDirectory: Bool) -> FileEntry {
        let created = values.creationDate ?? .distantPast
        return FileEntry(
            path: url.path,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            size: Int64(values.fileSize ?? 0),
            dateModified: values.contentModificationDate ?? .distantPast,
            dateCreated: created,
            dateAdded: values.addedToDirectoryDate ?? created,
            kind: values.localizedTypeDescription ?? (isDirectory ? "Carpeta" : "Documento")
        )
    }
}

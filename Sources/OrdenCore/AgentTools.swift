import Foundation

/// Nivel de riesgo de una herramienta del agente.
public enum AgentRisk: String, Codable, Sendable {
    case read
    case write
    case destructive
}

public enum AgentToolName: String, Codable, Sendable, CaseIterable {
    /// Búsqueda rápida por nombre (igual que ⌘4).
    case searchFiles
    /// Búsqueda del asistente/IA: lenguaje natural + contenido de archivos de texto (no Spotlight).
    case searchContent
    case listDirectory
    case getFileMetadata
    case openFile
    case previewFile
    case getStorageUsage
    case createDirectory
    case copyFiles
    case moveFiles
    case renameFiles
    case findDuplicates
    case organizeFiles
}

public struct AgentToolCall: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var name: AgentToolName
    public var arguments: [String: String]
    public var risk: AgentRisk

    public init(id: String = UUID().uuidString, name: AgentToolName, arguments: [String: String], risk: AgentRisk) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.risk = risk
    }

    public var labelSpanish: String {
        switch name {
        case .searchFiles:
            return "Buscar por nombre «\(arguments["query"] ?? "")»"
        case .searchContent:
            return "Buscar nombre + contenido «\(arguments["query"] ?? "")»"
        case .listDirectory:
            return "Listar carpeta"
        case .getFileMetadata:
            return "Mostrar info"
        case .openFile:
            let path = arguments["path"] ?? ""
            return "Abrir «\((path as NSString).lastPathComponent)»"
        case .previewFile:
            return "Vista rápida"
        case .getStorageUsage:
            return "Qué pesa más"
        case .findDuplicates:
            return "Buscar duplicados"
        case .createDirectory:
            return "Crear carpeta «\(arguments["name"] ?? "")»"
        case .copyFiles, .moveFiles:
            let count = pathsArgument.count
            let destination = ((arguments["destination"] ?? "?") as NSString).lastPathComponent
            let verb = name == .copyFiles ? "Copiar" : "Mover"
            return "\(verb) \(count <= 1 ? "1 ítem" : "\(count) ítems") → \(destination)"
        case .renameFiles:
            return "Renombrar → «\(arguments["newName"] ?? "")»"
        case .organizeFiles:
            return "Organizar por tipo"
        }
    }

    /// Los lotes se serializan con saltos de línea para no romper nombres que contengan «|».
    public var pathsArgument: [String] {
        let raw = arguments["paths"] ?? arguments["path"] ?? ""
        return raw
            .split(whereSeparator: { $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Detalle visible en la tarjeta de aprobación para revisar el origen real.
    public var approvalDetailsSpanish: String? {
        switch name {
        case .copyFiles, .moveFiles:
            let names = pathsArgument.map { ($0 as NSString).lastPathComponent }
            return names.isEmpty ? nil : "Origen: " + names.joined(separator: ", ")
        case .createDirectory:
            guard let parent = arguments["parent"] else { return nil }
            return "En: \(parent)"
        case .renameFiles:
            guard let path = arguments["path"] ?? pathsArgument.first else { return nil }
            return "Elemento: \(path)"
        default:
            return nil
        }
    }
}

public struct AgentPlan: Equatable, Sendable, Identifiable {
    public var id: String
    public var prompt: String
    public var summary: String
    public var steps: [AgentToolCall]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        prompt: String,
        summary: String,
        steps: [AgentToolCall],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.summary = summary
        self.steps = steps
        self.createdAt = createdAt
    }

    public var needsApproval: Bool {
        steps.contains { $0.risk != .read }
    }
}

public enum AgentPolicy {
    public static func risk(for name: AgentToolName) -> AgentRisk {
        switch name {
        case .searchFiles, .searchContent, .listDirectory, .getFileMetadata, .openFile, .previewFile, .getStorageUsage, .findDuplicates:
            return .read
        case .createDirectory, .copyFiles, .moveFiles, .renameFiles, .organizeFiles:
            return .write
        }
    }

    /// Home del usuario, `/Users/Shared` (sets compartidos / demos) y volúmenes montados.
    /// Resuelve symlinks y evita prefijos engañosos (`/Users/alguien-otro`).
    public static func isPathAllowed(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let resolved = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.resolvingSymlinksInPath().path
        let mountedVolume = resolved != "/Volumes" && isSameOrDescendant(resolved, of: "/Volumes")
        let sharedFolder = isSameOrDescendant(resolved, of: "/Users/Shared")
        return isSameOrDescendant(resolved, of: home) || mountedVolume || sharedFolder
    }

    public static func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        let expandedPath = (path as NSString).expandingTildeInPath
        let expandedRoot = (root as NSString).expandingTildeInPath
        let resolvedPath = URL(fileURLWithPath: expandedPath).standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedRoot = URL(fileURLWithPath: expandedRoot).standardizedFileURL.resolvingSymlinksInPath().path
        if resolvedPath == resolvedRoot { return true }
        let prefix = resolvedRoot == "/" ? "/" : resolvedRoot + "/"
        return resolvedPath.hasPrefix(prefix)
    }

    public static func isPathWithinScope(_ path: String, root: String) -> Bool {
        isSameOrDescendant(path, of: root)
    }
}

/// Parser de intenciones por reglas (sin LLM). Español e inglés básico.
public enum AgentIntentParser {
    /// Frases tipo «imágenes de hoy» / «música de hace 3 días» → atajo temporal.
    public static func inferShortcut(from lower: String) -> AssistantShortcut? {
        let folded = foldSpanish(lower)
        let window: ShortcutDateWindow?
        if folded.contains("hoy") {
            window = .today
        } else if folded.contains("ayer") {
            window = .yesterday
        } else if folded.contains("semana") {
            window = .lastDays(7)
        } else if let n = extractHaceDays(folded) {
            window = .lastDays(n)
        } else {
            window = nil
        }
        guard let window else { return nil }

        let categories: [FileCategory]
        if folded.contains("imagen") || folded.contains("foto") || folded.contains("picture") {
            categories = [.image]
        } else if folded.contains("musica") || folded.contains("audio") || folded.contains("cancion") {
            categories = [.audio]
        } else if folded.contains("video") || folded.contains("pelicula") {
            categories = [.video]
        } else if folded.contains("pdf") {
            categories = [.pdf]
        } else if folded.contains("documento") || folded.contains("docs") {
            categories = AssistantShortcut.documentCategories
        } else if folded.contains("archivo") || folded.contains("todo") || folded.contains("file") {
            // Vacío = cualquier tipo (p. ej. «archivos de hoy»).
            categories = []
        } else {
            return nil
        }

        let title: String
        if categories.isEmpty {
            title = "Archivos \(window.labelSpanish)"
        } else if categories == AssistantShortcut.documentCategories {
            title = "Documentos \(window.labelSpanish)"
        } else if let only = categories.first {
            title = "\(only.labelSpanish)s \(window.labelSpanish)"
        } else {
            title = "Archivos \(window.labelSpanish)"
        }
        return AssistantShortcut(title: title, categories: categories, dateWindow: window)
    }

    private static func extractHaceDays(_ lower: String) -> Int? {
        // Ya viene sin acentos: "hace 3 dias"
        let pattern = #"hace\s+(\d+)\s+dias"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: lower),
              let n = Int(lower[range]), n >= 1, n <= 365 else { return nil }
        return n
    }

    /// Quita acentos para matchear «imágenes» ≈ imagen.
    private static func foldSpanish(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
    }

    public static func plan(from prompt: String, currentPath: String) -> AgentPlan {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        var steps: [AgentToolCall] = []
        var summary = "Interpreté tu pedido"

        let isRename = lower.contains("renombr") || lower.contains("rename") || lower.contains("cambiar nombre") || lower.contains("cambia el nombre") || lower.contains("cambia nombre")
        let isCreateDir = (lower.contains("carpeta") || lower.contains("folder") || lower.contains("directorio") || lower.contains("mkdir")) && (lower.contains("crea") || lower.contains("nueva") || lower.contains("create") || lower.contains("nuevo") || lower.contains("mkdir"))
        let isOrganize = lower.contains("organiza") || lower.contains("organize") || lower.contains("ordenar por tipo")
        let isMove = lower.contains("mueve") || lower.contains("mover") || lower.contains("muéve") || lower.contains("move ") || lower.contains("move to") || lower.contains("move into")
        let isCopy = lower.contains("copia") || lower.contains("copiar") || lower.contains("copy ") || lower.contains("copy to") || lower.contains("copy into")
        let isWriteAction = isRename || isCreateDir || isOrganize || isMove || isCopy

        if isRename,
           let newName = extractQuoted(text) ?? extractAfter(text, keys: [
                "renombra el archivo a ", "renombrar el archivo a ",
                "renombra este archivo a ", "renombrar este archivo a ",
                "cambia el nombre a ", "cambiar el nombre a ",
                "cambiar nombre a ", "cambia nombre a ",
                "renombra a ", "renombrar a ",
                "renombra como ", "renombrar como ",
                "rename to ", "rename as ", "rename "
           ]) {
            steps.append(AgentToolCall(
                name: .renameFiles,
                arguments: ["newName": newName],
                risk: .write
            ))
            summary = "Renombrar selección a «\(newName)» (requiere aprobación)"
            return AgentPlan(prompt: text, summary: summary, steps: steps)
        }

        if isCreateDir,
           let folderName = extractQuoted(text) ?? extractAfter(text, keys: [
                "crea carpeta ", "crear carpeta ", "nueva carpeta ",
                "crea directorio ", "crear directorio ", "nuevo directorio ",
                "create folder ", "new folder ", "mkdir "
           ]) {
            steps.append(AgentToolCall(
                name: .createDirectory,
                arguments: ["name": folderName, "parent": currentPath],
                risk: .write
            ))
            summary = "Crear carpeta «\(folderName)» (requiere aprobación)"
            return AgentPlan(prompt: text, summary: summary, steps: steps)
        }

        // "qué pesa más" / "pesa" — no exigir "pesad*" (fallaba el chip del panel).
        if mentionsHeavy(lower) {
            steps.append(AgentToolCall(
                name: .getStorageUsage,
                arguments: ["path": currentPath],
                risk: .read
            ))
            summary = "Mostrar lo que más pesa aquí"
        }

        if mentionsDuplicates(lower) {
            steps.append(AgentToolCall(
                name: .findDuplicates,
                arguments: ["path": currentPath],
                risk: .read
            ))
            summary = "Buscar posibles duplicados en esta carpeta"
        }

        let wantsContentSearch =
            lower.contains("contenido")
            || lower.contains("dentro del")
            || lower.contains("dentro de")
            || lower.contains("que diga")
            || lower.contains("que dice")
            || lower.contains("factura")
            || lower.contains("contrato")
            || lower.contains("menciona")
            || lower.contains("containing")
            || lower.contains("inside ")

        let searchKeys = [
            "busca ", "buscar ", "buscame ", "búscame ", "buscando ",
            "encuentra ", "encuentrame ", "encuéntrame ",
            "localiza ", "localizame ", "localízame ",
            "muestra ", "muéstrame ", "mostrar ",
            "filtra por ", "filtrar por ", "filtrame ", "fíltrame ",
            "find ", "search "
        ]
        let wantsExplicitSearch = searchKeys.contains { lower.contains($0) }

        if !isWriteAction, (wantsExplicitSearch || wantsContentSearch || (!mentionsHeavy(lower) && !mentionsDuplicates(lower) && extractQuoted(text) != nil)),
           let rawTarget = (wantsExplicitSearch ? extractAfter(text, keys: searchKeys) : nil) ?? extractQuoted(text) {
            let name = sanitizeSearchQuery(rawTarget)
            if wantsContentSearch || (!name.hasPrefix(".") && name.split(separator: " ").count >= 3) {
                steps.append(AgentToolCall(
                    name: .searchContent,
                    arguments: ["query": name, "root": currentPath],
                    risk: .read
                ))
                summary = "Búsqueda asistente (nombre + contenido) «\(name)»"
            } else {
                steps.append(AgentToolCall(
                    name: .searchFiles,
                    arguments: ["query": name, "root": currentPath],
                    risk: .read
                ))
                summary = "Buscar por nombre «\(name)» bajo la carpeta actual"
            }
        }

        if !isWriteAction && lower.contains("pdf") {
            let alreadyPdf = steps.contains {
                $0.name == .searchFiles && ($0.arguments["query"] ?? "").lowercased().contains("pdf")
            }
            if !alreadyPdf {
                steps.append(AgentToolCall(
                    name: .searchFiles,
                    arguments: ["query": ".pdf", "root": currentPath],
                    risk: .read
                ))
                if summary == "Interpreté tu pedido" || mentionsHeavy(lower) {
                    summary = mentionsHeavy(lower)
                        ? "Peso + listar PDFs"
                        : "Listar PDFs en esta carpeta y subcarpetas"
                }
            }
        }

        if !isWriteAction && (lower.contains("lista") || lower.contains("list ")) && !wantsContentSearch {
            steps.append(AgentToolCall(
                name: .listDirectory,
                arguments: ["path": currentPath],
                risk: .read
            ))
            summary = "Listar contenido de la carpeta actual"
        }

        if lower.contains("organiza") || lower.contains("organize") || lower.contains("ordenar por tipo") {
            steps.append(AgentToolCall(
                name: .organizeFiles,
                arguments: ["path": currentPath],
                risk: .write
            ))
            summary = "Organizar por tipo en subcarpetas (requiere aprobación)"
        }

        if let dest = extractAfter(text, keys: [
            "mueve a ", "mover a ", "muéve a ", "move to ", "move into "
        ]) ?? (lower.contains("mueve") || lower.contains("mover") || lower.contains("move ")
               ? extractQuoted(text) : nil) {
            let destPath = resolveDestination(dest, currentPath: currentPath)
            steps.append(AgentToolCall(
                name: .moveFiles,
                arguments: ["destination": destPath, "note": text],
                risk: .write
            ))
            summary = "Mover selección → \(destPath) (requiere aprobación)"
        } else if lower.contains("mueve") || lower.contains("mover") || lower.contains("move ") {
            steps.append(AgentToolCall(
                name: .moveFiles,
                arguments: ["note": text],
                risk: .write
            ))
            summary = "Mover (indica destino: «mueve a Facturas»)"
        }

        if let dest = extractAfter(text, keys: [
            "copia a ", "copiar a ", "copy to ", "copy into "
        ]) {
            let destPath = resolveDestination(dest, currentPath: currentPath)
            steps.append(AgentToolCall(
                name: .copyFiles,
                arguments: ["destination": destPath, "note": text],
                risk: .write
            ))
            summary = "Copiar selección → \(destPath) (requiere aprobación)"
        }

        if steps.isEmpty {
            let candidate = extractAfter(text, keys: searchKeys) ?? text
            let sanitized = sanitizeSearchQuery(candidate)
            let isExt = sanitized.hasPrefix(".")
            let tool: AgentToolName = (!isExt && (wantsContentSearch || sanitized.split(separator: " ").count >= 3))
                ? .searchContent
                : .searchFiles
            steps.append(AgentToolCall(
                name: tool,
                arguments: ["query": sanitized, "root": currentPath],
                risk: .read
            ))
            summary = tool == .searchContent
                ? "Búsqueda asistente (nombre + contenido) «\(sanitized)»"
                : "Buscar por nombre «\(sanitized)» bajo la carpeta actual"
        }

        return AgentPlan(prompt: text, summary: summary, steps: steps)
    }

    /// Limpia frases coloquiales de búsqueda (ej: «archivos .wav» → «.wav», «canciones mp3» → «.mp3»).
    public static func sanitizeSearchQuery(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }

        // Si viene entre comillas explícitas, respetar literal
        if let quoted = extractQuoted(text) {
            return quoted
        }

        // Si contiene una extensión con punto (ej: .wav, *.wav, .tar.gz, etc.)
        if let dotIndex = text.firstIndex(of: ".") {
            let afterDot = text[dotIndex...]
            let extChars = afterDot.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "." }
            if !extChars.isEmpty && extChars.count <= 10 {
                return ".\(extChars.lowercased())"
            }
        }

        // Extensiones comunes mencionadas sin punto (ej: "archivos wav", "canciones mp3", "fotos jpg")
        let knownExtensions: Set<String> = [
            "wav", "mp3", "m4a", "flac", "aac", "ogg", "aiff",
            "png", "jpg", "jpeg", "gif", "svg", "webp", "heic",
            "pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "txt", "md", "csv",
            "zip", "rar", "tar", "gz", "7z", "dmg", "iso", "pkg",
            "mp4", "mov", "mkv", "avi", "webm"
        ]
        let lowerWords = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        for w in lowerWords {
            if knownExtensions.contains(w) {
                let low = text.lowercased()
                if low.contains("archivo") || low.contains("tipo") || low.contains("extension") || low.contains("extensión") || low.contains("terminad") || low.contains("formato") || low.contains("musica") || low.contains("música") || low.contains("audio") || low.contains("foto") || low.contains("video") || low.contains("document") {
                    return ".\(w)"
                }
            }
        }

        // Limpiar palabras de relleno comunes en español al inicio
        let allFillers = [
            "archivos con extension ", "archivos con extensión ",
            "archivos de tipo ", "archivos que terminen en ", "archivos terminados en ",
            "archivos que sean ", "archivos que contengan ", "archivos con nombre ",
            "archivos llamados ", "archivos de ", "archivos que ", "archivos ",
            "los archivos que ", "los archivos con ", "los archivos ",
            "los documentos de ", "los documentos con ", "los documentos ",
            "las fotos de ", "las fotos con ", "las fotos ",
            "los videos de ", "los videos con ", "los videos ",
            "las canciones de ", "las canciones con ", "las canciones ",
            "los audios de ", "los audios con ", "los audios ",
            "el archivo con ", "el archivo ", "las carpetas con ", "las carpetas ",
            "todos los archivos ", "todas las carpetas ",
            "documentos de ", "documentos con ", "documentos ",
            "fotos de ", "fotos con ", "fotos ",
            "videos de ", "videos con ", "videos ",
            "canciones de ", "canciones con ", "canciones ",
            "audios de ", "audios con ", "audios ",
            "el ", "la ", "los ", "las ", "un ", "una ", "de "
        ]
        var cleaned = text
        var changed = true
        while changed {
            changed = false
            for prefix in allFillers {
                if cleaned.lowercased().hasPrefix(prefix) {
                    cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    changed = true
                    break
                }
            }
        }

        let result = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n.,;!?«»\"'"))
        return result.isEmpty ? text : result
    }

    private static func mentionsHeavy(_ lower: String) -> Bool {
        lower.contains("pesad")
            || lower.contains("pesa más")
            || lower.contains("pesa mas")
            || lower.contains("qué pesa")
            || lower.contains("que pesa")
            || lower.contains("más pesa")
            || lower.contains("mas pesa")
            || lower.contains("cuánto ocupa")
            || lower.contains("cuanto ocupa")
            || lower.contains("espacio")
            || lower.contains("largest")
            || lower.contains("heaviest")
            || lower.contains("biggest")
    }

    private static func mentionsDuplicates(_ lower: String) -> Bool {
        lower.contains("duplicad")
            || lower.contains("duplicate")
            || lower.contains("hay copia")
            || lower.contains("copias iguales")
    }

    private static func extractQuoted(_ text: String) -> String? {
        let pairs: [(Character, Character)] = [
            ("«", "»"),
            ("\"", "\""),
            ("“", "”"),
            ("‘", "’"),
            ("'", "'")
        ]
        for (open, close) in pairs {
            if let first = text.firstIndex(of: open) {
                let rest = text[text.index(after: first)...]
                if let last = rest.lastIndex(of: close) {
                    let value = String(rest[..<last]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    private static func extractAfter(_ text: String, keys: [String]) -> String? {
        for key in keys {
            if let range = text.range(of: key, options: [.caseInsensitive, .diacriticInsensitive]) {
                var rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("«") || rest.hasPrefix("\"") || rest.hasPrefix("“") || rest.hasPrefix("'") {
                    if let quoted = extractQuoted(rest) {
                        return quoted
                    }
                }
                // Stop at trailing clauses like ", por favor" or ";"
                if let commaIdx = rest.firstIndex(of: ",") {
                    rest = String(rest[..<commaIdx])
                }
                if let semiIdx = rest.firstIndex(of: ";") {
                    rest = String(rest[..<semiIdx])
                }
                // Trim trailing punctuation (., !?), preserving extensions (.txt, .tar.gz)
                let cleaned = rest.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n.,;!?"))
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    /// Destino relativo a la carpeta actual, o ruta absoluta / ~.
    private static func resolveDestination(_ raw: String, currentPath: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return (trimmed as NSString).standardizingPath
        }
        if trimmed.hasPrefix("~") {
            return (trimmed as NSString).expandingTildeInPath
        }
        return (currentPath as NSString).appendingPathComponent(trimmed)
    }
}

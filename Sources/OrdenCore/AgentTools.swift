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

    /// Texto legible para la tarjeta de aprobación / chat.
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
            let p = arguments["path"] ?? ""
            return "Abrir «\((p as NSString).lastPathComponent)»"
        case .previewFile:
            return "Vista rápida"
        case .getStorageUsage:
            return "Qué pesa más"
        case .findDuplicates:
            return "Buscar duplicados"
        case .createDirectory:
            return "Crear carpeta «\(arguments["name"] ?? "")»"
        case .copyFiles:
            let n = pathsArgument.count
            let destRaw = arguments["destination"] ?? "?"
            let dest = (destRaw as NSString).lastPathComponent
            return n <= 1
                ? "Copiar 1 ítem → \(dest)"
                : "Copiar \(n) ítems → \(dest)"
        case .moveFiles:
            let n = pathsArgument.count
            let destRaw = arguments["destination"] ?? "?"
            let dest = (destRaw as NSString).lastPathComponent
            return n <= 1
                ? "Mover 1 ítem → \(dest)"
                : "Mover \(n) ítems → \(dest)"
        case .renameFiles:
            return "Renombrar → «\(arguments["newName"] ?? "")»"
        case .organizeFiles:
            return "Organizar por tipo"
        }
    }

    public var pathsArgument: [String] {
        let raw = arguments["paths"] ?? arguments["path"] ?? ""
        return raw
            .split(whereSeparator: { $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

    /// Detalle visible en la tarjeta de aprobación; el usuario debe poder revisar el origen real.
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

    /// Solo permite el home del usuario y volúmenes montados. Resuelve symlinks
    /// y comprueba límites de componentes para evitar prefijos como /Users/alguien-otro.
    public static func isPathAllowed(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let resolved = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.resolvingSymlinksInPath().path
        let mountedVolume = resolved != "/Volumes" && isSameOrDescendant(resolved, of: "/Volumes")
        return isSameOrDescendant(resolved, of: home) || mountedVolume
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

        if let name = extractQuoted(text) ?? extractAfter(text, keys: ["busca ", "buscar ", "encuentra ", "find ", "search "]) {
            if wantsContentSearch || name.split(separator: " ").count >= 3 {
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

        if lower.contains("pdf") {
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

        if (lower.contains("lista") || lower.contains("list ")) && !wantsContentSearch {
            steps.append(AgentToolCall(
                name: .listDirectory,
                arguments: ["path": currentPath],
                risk: .read
            ))
            summary = "Listar contenido de la carpeta actual"
        }

        if (lower.contains("carpeta") || lower.contains("folder") || lower.contains("mkdir")),
           let folderName = extractQuoted(text) ?? extractAfter(text, keys: [
                "crea carpeta ", "crear carpeta ", "nueva carpeta ",
                "create folder ", "mkdir "
           ]) {
            steps.append(AgentToolCall(
                name: .createDirectory,
                arguments: ["name": folderName, "parent": currentPath],
                risk: .write
            ))
            summary = "Crear carpeta «\(folderName)» (requiere aprobación)"
        }

        if lower.contains("renombr") || lower.contains("rename"),
           let newName = extractQuoted(text) ?? extractAfter(text, keys: [
                "renombra a ", "renombrar a ", "rename to ", "rename "
           ]) {
            steps.append(AgentToolCall(
                name: .renameFiles,
                arguments: ["newName": newName],
                risk: .write
            ))
            summary = "Renombrar selección a «\(newName)» (requiere aprobación)"
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
            let tool: AgentToolName = (wantsContentSearch || text.split(separator: " ").count >= 3)
                ? .searchContent
                : .searchFiles
            steps.append(AgentToolCall(
                name: tool,
                arguments: ["query": text, "root": currentPath],
                risk: .read
            ))
            summary = tool == .searchContent
                ? "Búsqueda asistente (nombre + contenido)"
                : "Búsqueda por nombre"
        }

        return AgentPlan(prompt: text, summary: summary, steps: steps)
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
        guard let first = text.firstIndex(of: "«") ?? text.firstIndex(of: "\""),
              let last = text.lastIndex(of: "»") ?? text.lastIndex(of: "\""),
              first < last else { return nil }
        let start = text.index(after: first)
        let value = String(text[start..<last]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func extractAfter(_ text: String, keys: [String]) -> String? {
        for key in keys {
            if let range = text.range(of: key, options: [.caseInsensitive, .diacriticInsensitive]) {
                let rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let cut = rest.split(whereSeparator: { $0 == "." || $0 == "," || $0 == ";" }).first.map(String.init) ?? rest
                let cleaned = cut.trimmingCharacters(in: .whitespaces)
                if cleaned.count >= 1 { return cleaned }
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

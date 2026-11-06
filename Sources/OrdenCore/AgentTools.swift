import Foundation

/// Nivel de riesgo de una herramienta del agente.
public enum AgentRisk: String, Codable, Sendable {
    case read
    case write
    case destructive
}

public enum AgentToolName: String, Codable, Sendable, CaseIterable {
    case searchFiles
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
        case .searchFiles, .listDirectory, .getFileMetadata, .openFile, .previewFile, .getStorageUsage, .findDuplicates:
            return .read
        case .createDirectory, .copyFiles, .renameFiles, .organizeFiles:
            return .write
        case .moveFiles:
            return .write
        }
    }

    /// Rutas fuera de home / volúmenes montados se rechazan salvo que estén bajo /Volumes o home.
    public static func isPathAllowed(_ path: String) -> Bool {
        let p = (path as NSString).standardizingPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if p.hasPrefix(home) { return true }
        if p.hasPrefix("/Volumes/") { return true }
        if p == "/" || p.hasPrefix("/Users/") { return true }
        return false
    }
}

/// Parser de intenciones por reglas (sin LLM). Español e inglés básico.
public enum AgentIntentParser {
    public static func plan(from prompt: String, currentPath: String) -> AgentPlan {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        var steps: [AgentToolCall] = []
        var summary = "Interpreté tu pedido"

        if lower.contains("pesad") || lower.contains("espacio") || lower.contains("largest") || lower.contains("heaviest") {
            steps.append(AgentToolCall(
                name: .getStorageUsage,
                arguments: ["path": currentPath],
                risk: .read
            ))
            summary = "Mostrar lo que más pesa aquí"
        }

        if lower.contains("duplicad") || lower.contains("duplicate") {
            steps.append(AgentToolCall(
                name: .findDuplicates,
                arguments: ["path": currentPath],
                risk: .read
            ))
            summary = "Buscar posibles duplicados en esta carpeta"
        }

        if let name = extractQuoted(text) ?? extractAfter(lower, keys: ["busca ", "buscar ", "encuentra ", "find ", "search "]) {
            steps.append(AgentToolCall(
                name: .searchFiles,
                arguments: ["query": name, "root": currentPath],
                risk: .read
            ))
            summary = "Buscar «\(name)» bajo la carpeta actual"
        }

        if lower.contains("pdf") && steps.isEmpty {
            steps.append(AgentToolCall(
                name: .searchFiles,
                arguments: ["query": ".pdf", "root": currentPath],
                risk: .read
            ))
            summary = "Listar PDFs en esta carpeta y subcarpetas"
        }

        if lower.contains("lista") || lower.contains("list ") || lower.contains("contenido") {
            steps.append(AgentToolCall(
                name: .listDirectory,
                arguments: ["path": currentPath],
                risk: .read
            ))
            summary = "Listar contenido de la carpeta actual"
        }

        if lower.contains("organiza") || lower.contains("organize") {
            steps.append(AgentToolCall(
                name: .organizeFiles,
                arguments: ["path": currentPath],
                risk: .write
            ))
            summary = "Proponer organizar por tipo (requiere aprobación)"
        }

        if lower.contains("mueve") || lower.contains("mover") || lower.contains("move ") {
            steps.append(AgentToolCall(
                name: .moveFiles,
                arguments: ["note": text],
                risk: .write
            ))
            summary = "Plan de movimiento (requiere aprobación y destinos claros)"
        }

        if steps.isEmpty {
            steps.append(AgentToolCall(
                name: .searchFiles,
                arguments: ["query": text, "root": currentPath],
                risk: .read
            ))
            summary = "Búsqueda general con tu texto"
        }

        return AgentPlan(prompt: text, summary: summary, steps: steps)
    }

    private static func extractQuoted(_ text: String) -> String? {
        guard let first = text.firstIndex(of: "«") ?? text.firstIndex(of: "\""),
              let last = text.lastIndex(of: "»") ?? text.lastIndex(of: "\""),
              first < last else { return nil }
        let start = text.index(after: first)
        let value = String(text[start..<last]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func extractAfter(_ lower: String, keys: [String]) -> String? {
        for key in keys {
            if let range = lower.range(of: key) {
                let rest = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let cut = rest.split(whereSeparator: { $0 == "." || $0 == "," || $0 == ";" }).first.map(String.init) ?? rest
                let cleaned = cut.trimmingCharacters(in: .whitespaces)
                if cleaned.count >= 2 { return cleaned }
            }
        }
        return nil
    }
}

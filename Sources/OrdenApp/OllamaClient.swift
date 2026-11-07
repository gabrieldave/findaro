import Foundation
import OrdenCore

/// Cliente Ollama local. Sin Ollama o desactivado → el caller usa reglas.
@MainActor
final class OllamaClient: ObservableObject {
    static let shared = OllamaClient()

    @Published var enabled = false
    @Published private(set) var available = false
    @Published private(set) var models: [String] = []
    @Published var selectedModel: String = "qwen2.5:3b"
    @Published var lastError: String?
    /// true mientras /api/generate está en curso.
    @Published private(set) var isGenerating = false

    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    var isReady: Bool { enabled && available }

    func applyPreferences(_ prefs: OrdenPreferences) {
        enabled = prefs.ollamaEnabled
        selectedModel = prefs.ollamaModel.isEmpty ? "qwen2.5:3b" : prefs.ollamaModel
    }

    /// Detecta si Ollama responde (sirve aunque esté desactivado en preferencias).
    func probe() async {
        do {
            let url = baseURL.appending(path: "api/tags")
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                markUnavailable(message: "Ollama no responde en :11434")
                return
            }
            struct Tags: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }
            let decoded = try JSONDecoder().decode(Tags.self, from: data)
            markAvailable(models: decoded.models.map(\.name))
        } catch {
            markUnavailable(message: error.localizedDescription)
        }
    }

    func refresh() async {
        await probe()
    }

    func markAvailable(models: [String]) {
        self.models = models
        available = true
        lastError = nil
        if let first = models.first, !models.contains(selectedModel) {
            selectedModel = first
        }
    }

    func markUnavailable(message: String) {
        available = false
        models = []
        lastError = message
    }

    enum ProposeOutcome: Sendable {
        case plan(AgentPlan)
        case unavailable
        /// Ollama respondió pero no se pudo usar (JSON malo, timeout, etc.).
        case failed(String)
    }

    /// Pide un plan JSON. Nunca deja colgado el chat sin feedback (timeout corto + errores).
    func proposePlan(prompt: String, currentPath: String) async -> ProposeOutcome {
        guard isReady else { return .unavailable }
        isGenerating = true
        defer { isGenerating = false }

        struct ReqBody: Encodable {
            let model: String
            let stream: Bool
            let prompt: String
            let format: String
            let options: [String: Int]
        }
        let system = """
        Eres el planificador de Ordena (explorador macOS). Responde SOLO un objeto JSON válido (sin markdown, sin <think>):
        {"summary":"frase corta","steps":[{"name":"TOOL","arguments":{"key":"valor"}}]}
        Tools lectura: searchFiles, searchContent, listDirectory, getStorageUsage, findDuplicates, openFile, previewFile, getFileMetadata
        Tools escritura: createDirectory, copyFiles, moveFiles, renameFiles, organizeFiles
        - Si piden peso/espacio Y pdfs: incluye getStorageUsage y searchFiles con query ".pdf".
        - searchFiles: solo nombre. searchContent: nombre + texto interno.
        - createDirectory: name + parent. moveFiles/copyFiles: destination. renameFiles: newName.
        Ámbito: carpeta actual y abajo. Sin borrar. Sin Spotlight.
        Ruta actual: \(currentPath)
        Usuario: \(prompt)
        """
        let body = ReqBody(
            model: selectedModel,
            stream: false,
            prompt: system,
            format: "json",
            options: ["num_predict": 256]
        )
        var request = URLRequest(url: baseURL.appending(path: "api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        // 9B en frío puede tardar; 45s + fallback a reglas (mejor que “no hace nada”).
        request.timeoutInterval = 45
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Respuesta inválida de Ollama"
                return .failed(lastError!)
            }
            guard http.statusCode == 200 else {
                lastError = "Ollama HTTP \(http.statusCode)"
                return .failed(lastError!)
            }
            struct Gen: Decodable { let response: String }
            let gen = try JSONDecoder().decode(Gen.self, from: data)
            if let plan = parsePlanJSON(gen.response, prompt: prompt) {
                lastError = nil
                return .plan(plan)
            }
            lastError = "El modelo no devolvió un plan JSON usable"
            return .failed(lastError!)
        } catch {
            lastError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    private func parsePlanJSON(_ raw: String, prompt: String) -> AgentPlan? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Qwen3 / reasoning: quitar bloques de pensamiento si vinieran.
        if let thinkOpen = text.range(of: "<think>"),
           let thinkClose = text.range(of: "</think>") {
            text.removeSubrange(thinkOpen.lowerBound..<thinkClose.upperBound)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stepsRaw = root["steps"] as? [[String: Any]] else { return nil }

        let summary = (root["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var steps: [AgentToolCall] = []

        // Un plan local no puede convertir una respuesta larga del modelo en cientos de acciones.
        for step in stepsRaw.prefix(12) {
            guard let nameRaw = step["name"] as? String,
                  let name = AgentToolName(rawValue: nameRaw) else { continue }

            let allowedKeys: Set<String>
            switch name {
            case .searchFiles, .searchContent:
                allowedKeys = ["query", "root"]
            case .listDirectory, .getStorageUsage, .findDuplicates, .organizeFiles:
                allowedKeys = ["path"]
            case .getFileMetadata, .openFile, .previewFile:
                allowedKeys = ["path"]
            case .createDirectory:
                allowedKeys = ["name", "parent"]
            case .copyFiles, .moveFiles:
                allowedKeys = ["paths", "path", "destination"]
            case .renameFiles:
                allowedKeys = ["path", "paths", "newName"]
            }

            var args: [String: String] = [:]
            if let dict = step["arguments"] as? [String: Any] {
                for (key, value) in dict where allowedKeys.contains(key) {
                    let string = stringifyArg(value)
                    guard !string.contains("\0"), string.count <= 8_192 else { continue }
                    args[key] = string
                }
            }
            steps.append(AgentToolCall(name: name, arguments: args, risk: AgentPolicy.risk(for: name)))
        }

        guard !steps.isEmpty else { return nil }
        let safeSummary = String((summary?.isEmpty == false ? summary! : "Plan de Ollama").prefix(240))
        return AgentPlan(prompt: prompt, summary: safeSummary, steps: steps)
    }

    private func stringifyArg(_ value: Any) -> String {
        if let strings = value as? [String] {
            return strings.joined(separator: "\n")
        }
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }
}

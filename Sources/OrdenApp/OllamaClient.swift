import Foundation
import OrdenCore

/// Cliente Ollama local (fase 3, opt-in). Sin Ollama o desactivado → reglas.
@MainActor
final class OllamaClient: ObservableObject {
    static let shared = OllamaClient()

    @Published var enabled = false
    @Published private(set) var available = false
    @Published private(set) var models: [String] = []
    @Published var selectedModel: String = "qwen2.5:3b"
    @Published var lastError: String?

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
            let (data, response) = try await URLSession.shared.data(from: url)
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

    /// Pide un plan JSON; si falla o está off, nil (caller usa reglas).
    func proposePlan(prompt: String, currentPath: String) async -> AgentPlan? {
        guard isReady else { return nil }
        struct ReqBody: Encodable {
            let model: String
            let stream: Bool
            let prompt: String
        }
        let system = """
        Eres el planificador de Ordena (explorador macOS). Responde SOLO JSON:
        {"summary":"...","steps":[{"name":"searchFiles|searchContent|listDirectory|getStorageUsage|findDuplicates|organizeFiles","arguments":{"key":"value"}}]}
        Reglas de búsqueda:
        - searchFiles: solo nombre de archivo (rápido; igual que ⌘4). Usa si piden un nombre corto o extensión (.pdf, factura.pdf).
        - searchContent: lenguaje natural o mirar DENTRO de archivos de texto. Usa si piden «facturas de marzo», «que diga…», «contratos», frases largas o contenido.
        Ámbito: carpeta actual y abajo. No uses Spotlight.
        Ruta actual: \(currentPath)
        Usuario: \(prompt)
        """
        let body = ReqBody(model: selectedModel, stream: false, prompt: system)
        var request = URLRequest(url: baseURL.appending(path: "api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        request.timeoutInterval = 60
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            struct Gen: Decodable { let response: String }
            let gen = try JSONDecoder().decode(Gen.self, from: data)
            return parsePlanJSON(gen.response, prompt: prompt)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func parsePlanJSON(_ raw: String, prompt: String) -> AgentPlan? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else { return nil }
        let json = String(trimmed[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        struct Payload: Decodable {
            struct Step: Decodable {
                let name: String
                let arguments: [String: String]?
            }
            let summary: String?
            let steps: [Step]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let steps: [AgentToolCall] = payload.steps.compactMap { step in
            guard let name = AgentToolName(rawValue: step.name) else { return nil }
            return AgentToolCall(
                name: name,
                arguments: step.arguments ?? [:],
                risk: AgentPolicy.risk(for: name)
            )
        }
        guard !steps.isEmpty else { return nil }
        return AgentPlan(
            prompt: prompt,
            summary: payload.summary ?? "Plan de Ollama",
            steps: steps
        )
    }
}

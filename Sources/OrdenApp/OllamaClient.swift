import Foundation
import OrdenCore

/// Cliente mínimo para Ollama local (opt-in). Sin Ollama → el agente usa reglas.
@MainActor
final class OllamaClient: ObservableObject {
    static let shared = OllamaClient()

    @Published private(set) var available = false
    @Published private(set) var models: [String] = []
    @Published var selectedModel: String = "qwen2.5:3b"
    @Published var lastError: String?

    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    func refresh() async {
        do {
            let url = baseURL.appending(path: "api/tags")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                available = false
                models = []
                lastError = "Ollama no responde en :11434"
                return
            }
            struct Tags: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }
            let decoded = try JSONDecoder().decode(Tags.self, from: data)
            models = decoded.models.map(\.name)
            available = true
            lastError = nil
            if let first = models.first, !models.contains(selectedModel) {
                selectedModel = first
            }
        } catch {
            available = false
            models = []
            lastError = error.localizedDescription
        }
    }

    /// Pide un plan JSON; si falla, nil (caller usa reglas).
    func proposePlan(prompt: String, currentPath: String) async -> AgentPlan? {
        guard available else { return nil }
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

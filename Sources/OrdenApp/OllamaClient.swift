import Foundation
import Combine
import OrdenCore

/// Cliente local de Ollama (http://127.0.0.1:11434).
/// No envía datos fuera del equipo.
@MainActor
final class OllamaClient: ObservableObject {
    static let shared = OllamaClient()

    @Published private(set) var available = false
    @Published private(set) var enabled = false
    @Published var selectedModel = "qwen2.5:7b"
    @Published private(set) var models: [String] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isGenerating = false

    /// Notifica al exterior si se auto-seleccionó un modelo disponible para persistirlo.
    var onModelAutoSelected: ((String) -> Void)?

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:11434")!
    }

    private init() {}

    func applyPreferences(_ prefs: OrdenPreferences) {
        enabled = prefs.ollamaEnabled
        if !prefs.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedModel = prefs.ollamaModel
        }
    }

    var isReady: Bool {
        enabled && available && !selectedModel.isEmpty
    }

    /// Comprueba si Ollama responde y lista modelos instalados.
    func probe() async {
        guard enabled else {
            available = false
            return
        }
        let url = baseURL.appending(path: "api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                markUnavailable(message: "Ollama no respondió en 127.0.0.1:11434")
                return
            }
            struct TagsResp: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }
            let decoded = try JSONDecoder().decode(TagsResp.self, from: data)
            let names = decoded.models.map(\.name)
            markAvailable(models: names)
        } catch {
            markUnavailable(message: "Ollama apagado o no instalado")
        }
    }

    func refresh() async {
        await probe()
    }

    func markAvailable(models: [String]) {
        self.models = models
        available = true
        lastError = nil
        if !models.contains(selectedModel), let first = models.first {
            selectedModel = first
            onModelAutoSelected?(first)
        }
    }

    func markUnavailable(message: String) {
        available = false
        models = []
        lastError = message
    }

    enum ProposeOutcome: Sendable {
        case plan(AgentPlan)
        case message(String)
        case unavailable
        /// Ollama respondió pero no se pudo usar (JSON malo, timeout, etc.).
        case failed(String)
    }

    /// Pide un plan JSON o respuesta conversacional.
    func proposePlan(prompt: String, currentPath: String) async -> ProposeOutcome {
        guard isReady else { return .unavailable }
        isGenerating = true
        defer { isGenerating = false }

        struct ReqBody: Encodable {
            let model: String
            let stream: Bool
            let prompt: String
            let format: String?
            let think: Bool?
            let options: [String: Int]
        }
        let system = """
        Eres el asistente inteligente de Findaro (explorador de archivos de macOS).
        - Si el usuario solo saluda (ej: hola, qué tal), responde amablemente en 1 o 2 frases explicando cómo le puedes ayudar a buscar, ordenar o mover archivos.
        - Si el usuario pide una acción de archivos (buscar, mover, copiar, renombrar, organizar, espacio, duplicados), responde con un objeto JSON válido (sin markdown):
        {"summary":"frase corta","steps":[{"name":"TOOL","arguments":{"param":"valor"}}]}
        Tools lectura: searchFiles (query), searchContent (query), listDirectory (path), getStorageUsage (path), findDuplicates (path), openFile (path), previewFile (path), getFileMetadata (path)
        Tools escritura: createDirectory (name, parent), copyFiles (destination), moveFiles (destination), renameFiles (newName), organizeFiles (path)
        - Si piden buscar archivos o una extensión (ej: .wav, *.wav, pdf, fotos): usa siempre searchFiles con el patrón o extensión en query (ej: .wav).
        - Si piden peso/espacio Y pdfs: incluye getStorageUsage y searchFiles con query ".pdf".
        Ámbito: carpeta actual y abajo. Sin borrar permanentemente.
        Ruta actual: \(currentPath)
        Usuario: \(prompt)
        """
        let body = ReqBody(
            model: selectedModel,
            stream: false,
            prompt: system,
            format: nil,
            think: false,
            options: ["num_predict": 512]
        )
        var request = URLRequest(url: baseURL.appending(path: "api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        request.timeoutInterval = 75
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Respuesta inválida del servidor Ollama"
                return .failed(lastError!)
            }
            guard http.statusCode == 200 else {
                if http.statusCode == 404 {
                    lastError = "El modelo «\(selectedModel)» no está instalado en Ollama (HTTP 404). Selecciona un modelo disponible."
                } else {
                    lastError = "Ollama devolvió HTTP \(http.statusCode)"
                }
                return .failed(lastError!)
            }
            struct Gen: Decodable { let response: String }
            let gen = try JSONDecoder().decode(Gen.self, from: data)
            let outcome = parsePlanJSON(gen.response, prompt: prompt)
            switch outcome {
            case .plan, .message:
                lastError = nil
            case .failed(let err):
                lastError = err
            case .unavailable:
                break
            }
            return outcome
        } catch {
            lastError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    private func parsePlanJSON(_ raw: String, prompt: String) -> ProposeOutcome {
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

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            let json = String(text[start...end])
            if let data = json.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let summary = (root["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                var steps: [AgentToolCall] = []
                if let stepsRaw = root["steps"] as? [[String: Any]] {
                    for step in stepsRaw.prefix(12) {
                        guard let nameRaw = step["name"] as? String,
                              let name = AgentToolName(rawValue: nameRaw) else { continue }
                        var args: [String: String] = [:]
                        if let dict = step["arguments"] as? [String: Any] {
                            for (key, value) in dict {
                                let str = stringifyArg(value)
                                guard !str.contains("\0"), str.count <= 8_192 else { continue }
                                args[key] = str
                            }
                            if let kVal = dict["key"] as? String {
                                switch name {
                                case .searchFiles, .searchContent:
                                    if args["query"] == nil { args["query"] = kVal }
                                case .listDirectory, .getStorageUsage, .findDuplicates, .organizeFiles:
                                    if args["path"] == nil { args["path"] = kVal }
                                default:
                                    break
                                }
                            }
                        }
                        steps.append(AgentToolCall(name: name, arguments: args, risk: AgentPolicy.risk(for: name)))
                    }
                }
                if !steps.isEmpty {
                    let safeSummary = String((summary?.isEmpty == false ? summary! : "Plan de Ollama").prefix(240))
                    return .plan(AgentPlan(prompt: prompt, summary: safeSummary, steps: steps))
                }
                if let summary, !summary.isEmpty {
                    return .message(summary)
                }
            }
        }

        // Si el modelo respondió texto conversacional (saludo, respuesta):
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count >= 2 {
            return .message(clean)
        }

        return .failed("El modelo no devolvió un plan ni respuesta usable")
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

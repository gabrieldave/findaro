import SwiftUI
import OrdenCore

/// Fase 2: asistente local por reglas (solo lectura). Ollama/voz se activan en fases 3–4.
struct AssistantPanel: View {
    @EnvironmentObject private var browser: BrowserModel
    @StateObject private var ollama = OllamaClient.shared
    @State private var draft = ""

    private let tips = [
        "busca pdf",
        "qué pesa más",
        "hay duplicados",
        "lista esta carpeta"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(ollama.available
                         ? "Ollama listo. Si no responde el modelo, cae a reglas locales (buscar, listar, pesados, duplicados)."
                         : "Sin IA aún: reglas locales. Los botones de abajo ya ejecutan acciones en la lista. Ollama = fase 3.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    tipChips

                    if let plan = browser.agentPlan, plan.needsApproval {
                        approvalCard(plan)
                    }

                    if !browser.agentLog.isEmpty {
                        logBlock
                    }
                }
                .padding(14)
            }
            Divider().opacity(0.35)
            composer
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(OrdenTheme.windowFill)
        .task { await ollama.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(OrdenTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asistente")
                    .font(.headline)
                Text(ollama.available ? "Ollama · \(ollama.selectedModel)" : "Reglas locales · ⌘5")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                browser.showAssistantPanel = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cerrar")
        }
        .padding(14)
    }

    private var tipChips: some View {
        FlowTips(tips: tips) { tip in
            draft = tip
            submit()
        }
    }

    private func approvalCard(_ plan: AgentPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Este plan modifica archivos")
                .font(.subheadline.weight(.semibold))
            Text(plan.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(plan.steps) { step in
                Text("• \(step.name.rawValue)")
                    .font(.caption2.monospaced())
            }
            HStack {
                Button("Cancelar") { browser.agentPlan = nil }
                Button("Aprobar") { browser.executeAgentPlan(approved: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var logBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Registro")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Limpiar") { browser.agentLog = [] }
                    .font(.caption2)
            }
            ForEach(Array(browser.agentLog.suffix(16).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ej: busca facturas…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            Button {
                submit()
            } label: {
                Label("Ejecutar", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(OrdenTheme.accent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await browser.runAssistant(prompt: text) }
        draft = ""
    }
}

/// Chips simples sin depender de Layout protocol complejo.
private struct FlowTips: View {
    let tips: [String]
    let onTap: (String) -> Void

    private func tipHelp(_ tip: String) -> String {
        switch tip {
        case "busca pdf": return "Busca archivos .pdf bajo la carpeta actual"
        case "qué pesa más": return "Ordena la lista: lo más pesado arriba"
        case "hay duplicados": return "Marca posibles duplicados (mismo nombre y tamaño)"
        case "lista esta carpeta": return "Recarga y muestra el contenido actual"
        default: return tip
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tips, id: \.self) { tip in
                Button {
                    onTap(tip)
                } label: {
                    Text(tip)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OrdenTheme.panelFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(tipHelp(tip))
            }
        }
    }
}

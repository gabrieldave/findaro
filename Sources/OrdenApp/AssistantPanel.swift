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
            chatArea
            Divider().opacity(0.35)
            tipsRow
            Divider().opacity(0.35)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrdenTheme.windowFill)
        .task { await ollama.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(OrdenTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asistente")
                    .font(.title3.weight(.semibold))
                Text(ollama.available ? "Ollama · \(ollama.selectedModel)" : "Te contesta aquí · ⌘5")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !browser.agentMessages.isEmpty {
                Button("Limpiar") { browser.clearAgentChat() }
                    .font(.subheadline)
            }
            Button {
                browser.showAssistantPanel = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cerrar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if browser.agentMessages.isEmpty {
                        welcomeCard
                    }
                    ForEach(browser.agentMessages) { msg in
                        chatBubble(msg)
                            .id(msg.id)
                    }
                    if let plan = browser.agentPlan, plan.needsApproval {
                        approvalCard(plan)
                    }
                }
                .padding(16)
            }
            .onChange(of: browser.agentMessages.count) { _, _ in
                if let last = browser.agentMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hola")
                .font(.title2.weight(.semibold))
            Text(
                ollama.available
                    ? "Escribe abajo o usa un atajo. Si el modelo no responde, uso reglas locales."
                    : "Todavía sin IA (eso es después). Mientras, con reglas locales: buscar, listar, lo más pesado y duplicados. La respuesta sale aquí en grande."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chatBubble(_ msg: BrowserModel.AgentChatMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 36) }
            Text(msg.text)
                .font(.body)
                .foregroundStyle(msg.role == .user ? Color.primary : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(
                    maxWidth: .infinity,
                    alignment: msg.role == .user ? .trailing : .leading
                )
                .background(
                    msg.role == .user
                        ? OrdenTheme.accent.opacity(0.28)
                        : OrdenTheme.panelFill,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .textSelection(.enabled)
            if msg.role == .assistant { Spacer(minLength: 12) }
        }
    }

    private func approvalCard(_ plan: AgentPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Esto modifica archivos")
                .font(.headline)
            Text(plan.summary)
                .font(.body)
                .foregroundStyle(.secondary)
            ForEach(plan.steps) { step in
                Text("• \(step.name.rawValue)")
                    .font(.subheadline.monospaced())
            }
            HStack {
                Button("Cancelar") { browser.agentPlan = nil }
                Button("Aprobar") { browser.executeAgentPlan(approved: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tipsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Atajos")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowTips(tips: tips) { tip in
                draft = tip
                submit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ej: busca facturas…", text: $draft)
                .font(.body)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            Button {
                submit()
            } label: {
                Label("Enviar", systemImage: "arrow.up.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(OrdenTheme.accent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .controlSize(.large)
        }
        .padding(16)
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await browser.runAssistant(prompt: text) }
        draft = ""
    }
}

/// Atajos del asistente (botones de ejemplo).
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
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tipHelp(tip))
            }
        }
    }
}

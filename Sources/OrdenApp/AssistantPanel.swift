import SwiftUI
import OrdenCore

/// Asistente del explorador: chat + atajos (muchos) + Ollama opt-in (fase 3).
struct AssistantPanel: View {
    @EnvironmentObject private var browser: BrowserModel
    @StateObject private var ollama = OllamaClient.shared
    @State private var draft = ""
    @State private var showNewShortcut = false

    private let quickActions = [
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
            shortcutsSection
            Divider().opacity(0.35)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrdenTheme.windowFill)
        .sheet(isPresented: $showNewShortcut) {
            ShortcutEditorSheet { shortcut in
                if let err = browser.addAssistantShortcut(shortcut) {
                    browser.appendAgentReply(err)
                }
            }
        }
        .task {
            ollama.applyPreferences(browser.store.preferences)
            await ollama.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(OrdenTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asistente")
                    .font(.title3.weight(.semibold))
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                browser.showOllamaSetupDialog = true
            } label: {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(ollama.isReady ? .green : OrdenTheme.accent)
            }
            .buttonStyle(.plain)
            .help("Configurar o detectar Ollama")
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

    private var headerSubtitle: String {
        if ollama.isReady {
            return "Ollama · \(ollama.selectedModel) · ⌘5"
        }
        if ollama.enabled {
            return "Ollama activado pero no responde · reglas · ⌘5"
        }
        return "Atajos + reglas · toca el cerebro para IA · ⌘5"
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
                "Soy el asistente del explorador. Usa tus atajos o escribe abajo. La IA (Ollama) es opcional: toca el icono del cerebro o Configurar Ollama."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                browser.showOllamaSetupDialog = true
            } label: {
                Label("Configurar Ollama…", systemImage: "brain.head.profile")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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

    /// Zona scrolleable: caben muchos atajos sin empujar el chat.
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mis atajos")
                    .font(.subheadline.weight(.semibold))
                Text("\(browser.assistantShortcuts.count)/\(AssistantShortcut.maxCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if browser.activeAssistantShortcut != nil {
                    Button("Quitar filtro") {
                        browser.clearAssistantShortcutFilter()
                    }
                    .font(.caption)
                }
                Button {
                    showNewShortcut = true
                } label: {
                    Label("Nuevo", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .disabled(browser.assistantShortcuts.count >= AssistantShortcut.maxCount)
                .help("Crear atajo: tipo + fechas (imágenes de hoy, etc.)")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(browser.assistantShortcuts) { shortcut in
                        shortcutRow(shortcut)
                    }
                    if browser.assistantShortcuts.isEmpty {
                        Text("Sin atajos aún. Crea uno: p. ej. imágenes de hoy.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxHeight: 168)

            Text("Acciones rápidas")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowTips(tips: quickActions) { tip in
                draft = tip
                submit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func shortcutRow(_ shortcut: AssistantShortcut) -> some View {
        let active = browser.activeAssistantShortcut?.id == shortcut.id
        return Button {
            browser.applyAssistantShortcut(shortcut)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: shortcutIcon(shortcut))
                    .foregroundStyle(active ? .orange : OrdenTheme.accent)
                Text(shortcut.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                active ? Color.orange.opacity(0.22) : OrdenTheme.panelFill,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Usar") { browser.applyAssistantShortcut(shortcut) }
            Button("Borrar", role: .destructive) {
                browser.deleteAssistantShortcut(id: shortcut.id)
            }
        }
        .help("Clic: filtrar · clic derecho: borrar")
    }

    private func shortcutIcon(_ shortcut: AssistantShortcut) -> String {
        if shortcut.categories == AssistantShortcut.documentCategories {
            return "doc.text"
        }
        return shortcut.categories.first?.symbolName ?? "line.3.horizontal.decrease.circle"
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ej: imágenes de hoy…", text: $draft)
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

// MARK: - Editor de atajo

struct ShortcutEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (AssistantShortcut) -> Void

    @State private var title = ""
    @State private var kind: Kind = .images
    @State private var window: WindowChoice = .today

    enum Kind: String, CaseIterable, Identifiable {
        case images, documents, audio, video, pdf, any
        var id: String { rawValue }
        var label: String {
            switch self {
            case .images: return "Imágenes"
            case .documents: return "Documentos"
            case .audio: return "Música / audio"
            case .video: return "Vídeos"
            case .pdf: return "PDF"
            case .any: return "Cualquier tipo"
            }
        }
        var categories: [FileCategory] {
            switch self {
            case .images: return [.image]
            case .documents: return AssistantShortcut.documentCategories
            case .audio: return [.audio]
            case .video: return [.video]
            case .pdf: return [.pdf]
            case .any: return []
            }
        }
    }

    enum WindowChoice: String, CaseIterable, Identifiable {
        case today, yesterday, days3, days7, days30
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Hoy"
            case .yesterday: return "Ayer"
            case .days3: return "Últimos 3 días"
            case .days7: return "Última semana"
            case .days30: return "Últimos 30 días"
            }
        }
        var dateWindow: ShortcutDateWindow {
            switch self {
            case .today: return .today
            case .yesterday: return .yesterday
            case .days3: return .lastDays(3)
            case .days7: return .lastDays(7)
            case .days30: return .lastDays(30)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nuevo atajo")
                .font(.title2.weight(.semibold))
            Text("Se guarda en el asistente. Puedes crear muchos; la lista hace scroll.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Tipo", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.label).tag($0) }
            }
            Picker("Cuándo", selection: $window) {
                ForEach(WindowChoice.allCases) { Text($0.label).tag($0) }
            }
            TextField("Nombre (opcional)", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("Guardar") {
                    let cats = kind.categories
                    let win = window.dateWindow
                    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let shortcut = AssistantShortcut(
                        title: name.isEmpty ? autoTitle(kind: kind, window: win) : name,
                        categories: cats,
                        dateWindow: win
                    )
                    onSave(shortcut)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func autoTitle(kind: Kind, window: ShortcutDateWindow) -> String {
        "\(kind.label) \(window.labelSpanish)"
    }
}

/// Acciones rápidas fijas (no son atajos guardados).
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
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tipHelp(tip))
            }
        }
    }
}

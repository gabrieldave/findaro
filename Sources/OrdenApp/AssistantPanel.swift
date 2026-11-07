import SwiftUI
import OrdenCore

/// Asistente del explorador: chat + atajos (muchos) + Ollama opt-in (fase 3).
struct AssistantPanel: View {
    @EnvironmentObject private var browser: BrowserModel
    @StateObject private var ollama = OllamaClient.shared
    @StateObject private var voice = VoiceCaptureController.shared
    @State private var draft = ""
    @State private var showNewShortcut = false
    @State private var holdingMic = false
    @State private var busyDotCount = 1

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
            ShortcutEditorSheet(existing: nil) { shortcut in
                if let err = browser.addAssistantShortcut(shortcut) {
                    browser.appendAgentReply(err)
                }
            }
        }
        .onAppear {
            // El monitor de teclado (⌃Espacio) también asigna onFinished; reforzamos aquí
            // por si el panel se abrió sin reinstalar el monitor.
            voice.onFinished = { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task { @MainActor in
                    await browser.runAssistant(prompt: trimmed)
                }
            }
        }
        .task {
            ollama.applyPreferences(browser.store.preferences)
            await ollama.refresh()
        }
        .task(id: browser.agentBusy) {
            guard browser.agentBusy else {
                busyDotCount = 1
                return
            }
            while !Task.isCancelled, browser.agentBusy {
                try? await Task.sleep(nanoseconds: 400_000_000)
                busyDotCount = busyDotCount >= 3 ? 1 : busyDotCount + 1
            }
        }
    }

    private var agentBusyBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 2) {
                Text(busyTitle)
                    .font(.subheadline.weight(.semibold))
                Text("Espera un momento — no cierres el panel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrdenTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OrdenTheme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private var busyTitle: String {
        let base = browser.agentProgressLabel.isEmpty ? "Trabajando" : browser.agentProgressLabel
        return base + String(repeating: ".", count: busyDotCount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(OrdenTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ollama.isReady ? "Asistente + Ollama" : "Asistente")
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

            // Instrucciones fijas: este panel ES el chat con Ollama.
            ollamaHowToBanner
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var ollamaHowToBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ollama.isReady {
                Text("Aquí hablas con Ollama («\(ollama.selectedModel)»)")
                    .font(.subheadline.weight(.semibold))
                Text("Escribe abajo o mantén el micrófono / ⌃Espacio → Enviar. Todo es local en tu Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if ollama.enabled {
                Text("Ollama no responde ahora")
                    .font(.subheadline.weight(.semibold))
                Text("Los atajos y reglas siguen. Toca el cerebro verde/azul para detectar otra vez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sin Ollama: atajos y reglas (calidad básica)")
                    .font(.subheadline.weight(.semibold))
                Text("Para frases libres con IA: toca el cerebro → Detectar / Activar Ollama.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (ollama.isReady ? Color.green : OrdenTheme.accent).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var headerSubtitle: String {
        if browser.agentBusy {
            let base = browser.agentProgressLabel.isEmpty ? "Trabajando" : browser.agentProgressLabel
            return base + String(repeating: ".", count: busyDotCount)
        }
        if ollama.isReady {
            return "Chat local · \(ollama.selectedModel) · ⌘5"
        }
        if ollama.enabled {
            return "Ollama activado pero no responde · reglas · ⌘5"
        }
        return "Atajos + reglas · cerebro = Ollama · ⌘5"
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
                    if browser.agentBusy {
                        agentBusyBanner
                            .id("agent-busy")
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
            .onChange(of: browser.agentBusy) { _, busy in
                if busy {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("agent-busy", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ollama.isReady ? "Listo para chatear" : "Hola")
                .font(.title2.weight(.semibold))
            if ollama.isReady {
                Text(
                    "Este panel es tu chat con Ollama. Prueba: «qué pesa más y si hay pdfs», «organiza por tipo», «crea carpeta Facturas»."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    "Atajos, texto o voz. Sin Ollama: reglas básicas. Con Ollama (cerebro arriba): frases libres con más calidad."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    browser.showOllamaSetupDialog = true
                } label: {
                    Label("Activar Ollama…", systemImage: "brain.head.profile")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.large)
            }
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
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.steps) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.risk == .destructive ? "exclamationmark.triangle.fill" : "pencil.circle.fill")
                            .foregroundStyle(.orange)
                        Text(step.labelSpanish)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Button("Cancelar") {
                    browser.agentPlan = nil
                    browser.pendingAgentApproval = nil
                    browser.appendAgentReply("Cancelé el plan. No toqué nada.")
                }
                Button("Aprobar y ejecutar") { browser.executeAgentPlan(approved: true) }
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
            if browser.agentBusy {
                agentBusyBanner
            }

            if voice.phase != .idle || holdingMic {
                Text(voice.statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(holdingMic || voice.isListening ? .orange : .secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        (holdingMic || voice.isListening ? Color.orange : OrdenTheme.accent).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }

            TextField(
                ollama.isReady
                    ? "Habla con Ollama… ej: qué pesa más y si hay pdfs"
                    : "Ej: imágenes de hoy… (sin Ollama = reglas)",
                text: $draft
            )
                .font(.body)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
                .disabled(holdingMic || voice.isListening || browser.agentBusy)

            HStack(spacing: 10) {
                pushToTalkButton
                Button {
                    submit()
                } label: {
                    Label(
                        ollama.isReady ? "Enviar a Ollama" : "Enviar",
                        systemImage: "arrow.up.circle.fill"
                    )
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .disabled(
                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || holdingMic
                        || browser.agentBusy
                )
                .controlSize(.large)
            }

            Text(
                ollama.isReady
                    ? "Micrófono o ⌃Espacio = dictar. Enviar = Ollama interpreta y actúa en esta carpeta."
                    : "Micrófono o ⌃Espacio = dictar. Sin Ollama solo atajos/reglas."
            )
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    private var pushToTalkButton: some View {
        Image(systemName: holdingMic || voice.isListening ? "mic.fill" : "mic.circle.fill")
            .font(.system(size: 28))
            .foregroundStyle(holdingMic || voice.isListening ? Color.white : OrdenTheme.accent)
            .frame(width: 48, height: 40)
            .background(
                holdingMic || voice.isListening ? Color.orange : OrdenTheme.panelFill,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holdingMic else { return }
                        holdingMic = true
                        voice.beginPushToTalk()
                    }
                    .onEnded { _ in
                        holdingMic = false
                        voice.endPushToTalk()
                    }
            )
            .help("Mantén para hablar · atajo ⌃Espacio (español)")
            .accessibilityLabel("Mantener para hablar")
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await browser.runAssistant(prompt: text) }
        draft = ""
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

import SwiftUI
import OrdenCore

/// Asistente del explorador: chat + atajos (muchos) + Ollama opt-in (fase 3).
struct AssistantPanel: View {
    @AppStorage("findaro_app_language") private var appLangStorage: String = "auto"
    @EnvironmentObject private var browser: BrowserModel
    @StateObject private var ollama = OllamaClient.shared
    @StateObject private var voice = VoiceCaptureController.shared
    @State private var draft = ""
    @State private var showNewShortcut = false
    @State private var holdingMic = false
    @State private var busyDotCount = 1
    @State private var showShortcuts = false
    @FocusState private var composerFocused: Bool

    private var quickActions: [String] {
        [
            L10n.s("busca pdf", "find pdfs"),
            L10n.s("qué pesa más", "largest files"),
            L10n.s("hay duplicados", "any duplicates"),
            L10n.s("lista esta carpeta", "list this folder")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            chatArea
                .frame(minHeight: 120, maxHeight: .infinity)
                .layoutPriority(0)
            Divider().opacity(0.35)
            DisclosureGroup(isExpanded: $showShortcuts) {
                shortcutsSection
            } label: {
                Text(L10n.s("Atajos y acciones rápidas", "Shortcuts & Quick Actions"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            Divider().opacity(0.35)
            composer
                .layoutPriority(1)
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
            showShortcuts = !OllamaClient.shared.isReady
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                composerFocused = true
            }
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
        .onChange(of: composerFocused) { _, focused in
            browser.isAssistantFocused = focused
        }
        .onChange(of: browser.isAssistantFocused) { _, focused in
            if !focused {
                composerFocused = false
            }
        }
        .onDisappear {
            browser.isAssistantFocused = false
            composerFocused = false
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
                    Text(ollama.isReady ? L10n.s("Asistente + Ollama", "Assistant + Ollama") : L10n.s("Asistente", "Assistant"))
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
                .help(L10n.s("Configurar o detectar Ollama", "Configure or detect Ollama"))
                if !browser.agentMessages.isEmpty {
                    Button(L10n.s("Limpiar", "Clear")) { browser.clearAgentChat() }
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
                .help(L10n.s("Cerrar", "Close"))
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
                Text(L10n.s("Aquí hablas con Ollama («\(ollama.selectedModel)»)", "Chat with Ollama here («\(ollama.selectedModel)»)"))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.s("Escribe abajo o mantén el micrófono / ⌃Espacio → Enviar. Todo es local en tu Mac.", "Type below or hold microphone / ⌃Space → Send. Everything is local on your Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if ollama.enabled {
                Text(L10n.s("Ollama no responde ahora", "Ollama is not responding"))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.s("Los atajos y reglas siguen. Toca el cerebro verde/azul para detectar otra vez.", "Shortcuts and rules still work. Click the brain icon to detect again."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.s("Sin Ollama: atajos y reglas (calidad básica)", "Without Ollama: shortcuts and rules (basic mode)"))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.s("Para frases libres con IA: toca el cerebro → Detectar / Activar Ollama.", "For natural language AI: click the brain icon → Detect / Enable Ollama."))
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
            let base = browser.agentProgressLabel.isEmpty ? L10n.s("Trabajando", "Working") : browser.agentProgressLabel
            return base + String(repeating: ".", count: busyDotCount)
        }
        if ollama.isReady {
            return "\(L10n.s("Chat local", "Local chat")) · \(ollama.selectedModel) · ⌘5"
        }
        if ollama.enabled {
            return L10n.s("Ollama activado pero no responde · reglas · ⌘5", "Ollama enabled but not responding · rules · ⌘5")
        }
        return L10n.s("Atajos + reglas · cerebro = Ollama · ⌘5", "Shortcuts + rules · AI engine = Ollama · ⌘5")
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
            Text(ollama.isReady ? "\(L10n.s("Chat con", "Chat with")) \(ollama.selectedModel)" : L10n.s("Hola", "Hello"))
                .font(.title2.weight(.semibold))
            if ollama.isReady {
                Text(
                    L10n.s(
                        "Escribe abajo, como en ChatGPT. Verás tus mensajes y las respuestas aquí. Mientras piensa, aparece «Trabajando…».",
                        "Type below, just like in ChatGPT. You will see your messages and answers here. While thinking, «Working…» appears."
                    )
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text(L10n.s("Prueba: «qué pesa más y si hay pdfs» · «crea carpeta Facturas»", "Try: «largest files and any pdfs» · «create folder Invoices»"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text(
                    L10n.s(
                        "Atajos, texto o voz. Sin Ollama: reglas básicas. Con Ollama (cerebro arriba): frases libres con más calidad.",
                        "Shortcuts, text, or voice. Without Ollama: basic rules. With Ollama: flexible natural language with higher quality."
                    )
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    browser.showOllamaSetupDialog = true
                } label: {
                    Label(L10n.s("Activar Ollama…", "Enable Ollama…"), systemImage: "brain.head.profile")
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
        let isUser = msg.role == .user
        return HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 28) }
            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 22, height: 22)
                    .background(OrdenTheme.accent.opacity(0.15), in: Circle())
                    .padding(.top, 4)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "Tú" : (ollama.isReady ? ollama.selectedModel : "Asistente"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(msg.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(
                        maxWidth: .infinity,
                        alignment: isUser ? .trailing : .leading
                    )
                    .background(
                        isUser
                            ? OrdenTheme.accent.opacity(0.28)
                            : OrdenTheme.panelFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .textSelection(.enabled)
            }
            if isUser {
                Image(systemName: "person.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(OrdenTheme.panelFill, in: Circle())
                    .padding(.top, 4)
            }
            if !isUser { Spacer(minLength: 8) }
        }
    }

    private func approvalCard(_ plan: AgentPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.s("Esto modifica archivos", "This modifies files"))
                .font(.headline)
            Text(plan.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.steps) { step in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: step.risk == .destructive ? "exclamationmark.triangle.fill" : "pencil.circle.fill")
                                .foregroundStyle(.orange)
                            Text(step.labelLocalized)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let details = step.approvalDetailsLocalized {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 24)
                        }
                    }
                }
            }
            HStack {
                Button(L10n.s("Cancelar", "Cancel")) {
                    browser.agentPlan = nil
                    browser.pendingAgentApproval = nil
                    browser.appendAgentReply(L10n.s("Cancelé el plan. No toqué nada.", "Plan cancelled. Nothing was modified."))
                }
                Button(L10n.s("Aprobar y ejecutar", "Approve & Execute")) { browser.executeAgentPlan(approved: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Atajos colapsables: el chat es lo principal.
    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.s("Mis atajos", "My Shortcuts"))
                    .font(.caption.weight(.semibold))
                Text("\(browser.assistantShortcuts.count)/\(AssistantShortcut.maxCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if browser.activeAssistantShortcut != nil {
                    Button(L10n.s("Quitar filtro", "Clear filter")) {
                        browser.clearAssistantShortcutFilter()
                    }
                    .font(.caption)
                }
                Button {
                    showNewShortcut = true
                } label: {
                    Label(L10n.s("Nuevo", "New"), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .disabled(browser.assistantShortcuts.count >= AssistantShortcut.maxCount)
                .help(L10n.s("Crear atajo: tipo + fechas (imágenes de hoy, etc.)", "Create shortcut: type + dates (today's images, etc.)"))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(browser.assistantShortcuts) { shortcut in
                        shortcutRow(shortcut)
                    }
                    if browser.assistantShortcuts.isEmpty {
                        Text(L10n.s("Sin atajos aún. Crea uno: p. ej. imágenes de hoy.", "No shortcuts yet. Create one: e.g. today's images."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 120)

            Text(L10n.s("Acciones rápidas", "Quick Actions"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowTips(tips: quickActions) { tip in
                draft = tip
                submit()
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func shortcutRow(_ shortcut: AssistantShortcut) -> some View {
        let active = browser.activeAssistantShortcut?.id == shortcut.id
        return Button {
            browser.applyAssistantShortcut(shortcut)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: shortcutIcon(shortcut))
                    .foregroundStyle(active ? .orange : OrdenTheme.accent)
                Text(shortcut.displayTitle)
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
            Button(L10n.s("Usar", "Use")) { browser.applyAssistantShortcut(shortcut) }
            Button(L10n.s("Borrar", "Delete"), role: .destructive) {
                browser.deleteAssistantShortcut(id: shortcut.id)
            }
        }
        .help(L10n.s("Clic: filtrar · clic derecho: borrar", "Click: filter · right-click: delete"))
    }

    private func shortcutIcon(_ shortcut: AssistantShortcut) -> String {
        if shortcut.categories == AssistantShortcut.documentCategories {
            return "doc.text"
        }
        return shortcut.categories.first?.symbolName ?? "line.3.horizontal.decrease.circle"
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if voice.phase != .idle || holdingMic {
                Text(voice.statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(holdingMic || voice.isListening ? .orange : .secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        (holdingMic || voice.isListening ? Color.orange : OrdenTheme.accent).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }

            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(
                        ollama.isReady
                            ? L10n.s("Escribe aquí como en ChatGPT…\nej: qué pesa más y si hay pdfs", "Type here like in ChatGPT…\ne.g.: largest files and any pdfs")
                            : L10n.s("Escribe aquí… (sin Ollama = reglas / atajos)", "Type here… (without Ollama = rules / shortcuts)")
                    )
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 44, maxHeight: 80)
                    .padding(6)
                    .focused($composerFocused)
                    .disabled(holdingMic || voice.isListening || browser.agentBusy)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        // Return = enviar · ⇧Return = nueva línea
                        if press.modifiers.contains(.shift) { return .ignored }
                        submit()
                        return .handled
                    }
            }
            .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        composerFocused ? OrdenTheme.accent.opacity(0.55) : OrdenTheme.hairline,
                        lineWidth: composerFocused ? 1.5 : 1
                    )
            )

            HStack(spacing: 8) {
                pushToTalkButton
                Button {
                    submit()
                } label: {
                    Label(
                        browser.agentBusy
                            ? L10n.s("Trabajando…", "Working…")
                            : (ollama.isReady ? "\(L10n.s("Enviar a", "Send to")) \(ollama.selectedModel)" : L10n.s("Enviar", "Send")),
                        systemImage: browser.agentBusy ? "hourglass" : "arrow.up.circle.fill"
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
                    ? L10n.s("↩ enviar · ⇧↩ nueva línea · micrófono o ⌃Espacio = dictar. Respuestas arriba, en el chat.", "↩ send · ⇧↩ new line · mic or ⌃Space = dictate. Responses above in chat.")
                    : L10n.s("↩ enviar · micrófono o ⌃Espacio = dictar. Sin Ollama solo atajos/reglas.", "↩ send · mic or ⌃Space = dictate. Without Ollama shortcuts/rules only.")
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
            .help(L10n.s("Mantén para hablar · atajo ⌃Espacio", "Hold to speak · shortcut ⌃Space"))
            .accessibilityLabel(L10n.s("Mantener para hablar", "Hold to speak"))
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
        case "busca pdf", "find pdfs": return L10n.s("Busca archivos .pdf bajo la carpeta actual", "Search for .pdf files in active folder")
        case "qué pesa más", "largest files": return L10n.s("Ordena la lista: lo más pesado arriba", "Sort list: largest files on top")
        case "hay duplicados", "any duplicates": return L10n.s("Marca posibles duplicados (mismo nombre y tamaño)", "Flag possible duplicates (matching name & size)")
        case "lista esta carpeta", "list this folder": return L10n.s("Recarga y muestra el contenido actual", "Reload and show current contents")
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

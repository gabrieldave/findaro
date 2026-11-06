import SwiftUI
import OrdenCore

struct AssistantPanel: View {
    @EnvironmentObject private var browser: BrowserModel
    @StateObject private var voice = VoiceCaptureController.shared
    @StateObject private var ollama = OllamaClient.shared
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Asistente", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Button {
                    browser.showAssistantPanel = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider().opacity(0.35)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Lenguaje natural (local). Sin modelo usa reglas; con Ollama usa el LLM.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let plan = browser.agentPlan {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(plan.summary)
                                .font(.subheadline.weight(.semibold))
                            ForEach(plan.steps) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: step.risk == .read ? "eye" : "pencil.tip")
                                        .foregroundStyle(step.risk == .read ? OrdenTheme.accent : .orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.name.rawValue)
                                            .font(.caption.weight(.bold))
                                        Text(step.arguments.map { "\($0.key)=\($0.value)" }.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            HStack {
                                if plan.needsApproval {
                                    Button("Aprobar y ejecutar") {
                                        browser.executeAgentPlan(approved: true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button("Cancelar plan") {
                                        browser.agentPlan = nil
                                    }
                                } else {
                                    Button("Ejecutar") {
                                        browser.executeAgentPlan(approved: true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .padding(10)
                        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10))
                    }

                    if !browser.agentLog.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Registro")
                                .font(.caption.weight(.semibold))
                            ForEach(browser.agentLog.suffix(12), id: \.self) { line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if case .error(let msg) = voice.phase {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    } else if !voice.transcript.isEmpty {
                        Text("Voz: \(voice.transcript)")
                            .font(.caption)
                    }
                }
                .padding(12)
            }

            Divider().opacity(0.35)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Ej: busca facturas PDF…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submit() }
                    Button("Ir") { submit() }
                        .keyboardShortcut(.return, modifiers: .command)
                }

                HStack(spacing: 8) {
                    Button {
                        if voice.isListening {
                            voice.endPushToTalk()
                            Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty {
                                    draft = text
                                    await browser.runAssistant(prompt: text)
                                }
                            }
                        } else {
                            voice.beginPushToTalk()
                        }
                    } label: {
                        Label(
                            voice.isListening ? "Soltar (escuchando…)" : "Mantener para hablar",
                            systemImage: voice.isListening ? "waveform" : "mic"
                        )
                    }
                    .tint(voice.isListening ? .orange : OrdenTheme.accent)

                    if ollama.available {
                        Text("Ollama · \(ollama.selectedModel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Reglas locales")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .background(OrdenTheme.windowFill)
        .task {
            await ollama.refresh()
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await browser.runAssistant(prompt: text) }
    }
}

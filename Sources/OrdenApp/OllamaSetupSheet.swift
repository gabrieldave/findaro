import SwiftUI
import AppKit
import OrdenCore

/// Ventana formal: detectar Ollama, activarlo, o seguir solo con reglas/atajos.
struct OllamaSetupSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @StateObject private var ollama = OllamaClient.shared
    @State private var checking = false

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "brain.head.profile",
                title: L10n.s("Inteligencia local (Ollama)", "Local AI (Ollama)"),
                subtitle: L10n.s("Opcional. Si no la quieres, el asistente sigue con atajos y reglas.", "Optional. If disabled, the assistant continues with shortcuts and rule matching.")
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                statusCard

                OrdenDialogSection(title: L10n.s("Qué hace", "What it does")) {
                    Text(L10n.s("Con Ollama en este Mac, el asistente puede entender frases más libres. Todo queda en tu computadora: no se manda a la nube.", "With Ollama on this Mac, the assistant can understand natural language queries. Everything stays on your computer: zero cloud transmission."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if ollama.available && !ollama.models.isEmpty {
                    OrdenDialogSection(title: L10n.s("Modelo", "Model")) {
                        Picker(L10n.s("Modelo", "Model"), selection: Binding(
                            get: { ollama.selectedModel },
                            set: { browser.setOllamaModel($0) }
                        )) {
                            ForEach(ollama.models, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }
                }

                OrdenDialogHintBox(rows: hintRows)

                HStack(spacing: 10) {
                    Button {
                        Task { await detect() }
                    } label: {
                        Label(checking ? L10n.s("Detectando…", "Detecting…") : L10n.s("Detectar otra vez", "Detect Again"), systemImage: "arrow.clockwise")
                    }
                    .disabled(checking)

                    if !ollama.available {
                        Button(L10n.s("Abrir Ollama", "Open Ollama")) {
                            openOllamaApp()
                        }
                        Button(L10n.s("Bajar Ollama…", "Download Ollama…")) {
                            if let url = URL(string: "https://ollama.com/download") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                .controlSize(.regular)
            }
            .padding(20)
        } footer: {
            footer
        }
        .task { await detect() }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title)
                .foregroundStyle(statusTint)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusIcon: String {
        if checking { return "ellipsis.circle" }
        if ollama.available { return "checkmark.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var statusTint: Color {
        if checking { return .secondary }
        if ollama.available { return .green }
        return .orange
    }

    private var statusTitle: String {
        if checking { return L10n.s("Buscando Ollama…", "Searching for Ollama…") }
        if ollama.available {
            return ollama.enabled ? L10n.s("Ollama listo y activado", "Ollama ready and enabled") : L10n.s("Ollama detectado", "Ollama detected")
        }
        return L10n.s("No encuentro Ollama", "Ollama not found")
    }

    private var statusDetail: String {
        if checking { return L10n.s("Mirando http://127.0.0.1:11434", "Checking http://127.0.0.1:11434") }
        if ollama.available {
            let n = ollama.models.count
            return n == 1
                ? L10n.s("Hay 1 modelo instalado. Puedes activarlo abajo.", "1 model installed. You can enable it below.")
                : L10n.s("Hay \(n) modelos. Elige uno y actívalo, o sigue sin IA.", "\(n) models found. Choose one and enable it, or continue without AI.")
        }
        return ollama.lastError
            ?? L10n.s("No pasa nada: el asistente usa atajos y reglas. Si instalas Ollama después, vuelve a detectar.", "No problem: assistant uses rules and shortcuts. If you install Ollama later, detect again.")
    }

    private var hintRows: [OrdenDialogHintBox.Row] {
        if ollama.available {
            return [
                .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("Activar = el asistente usa el modelo cuando hace falta.", "Enable = assistant uses local model when helpful.")),
                .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("Si Ollama se apaga, Findaro cae solo a reglas (no se rompe).", "If Ollama shuts down, Findaro falls back smoothly to rules.")),
                .init(icon: "xmark.circle.fill", tint: .secondary, text: L10n.s("No es obligatorio. Sin IA también funcionan atajos y búsquedas.", "Optional. Shortcuts and recursive searches work without AI."))
            ]
        }
        return [
            .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("Sin Ollama: atajos (imágenes de hoy…) y frases sencillas siguen.", "Without Ollama: shortcuts (today's images…) and simple patterns work.")),
            .init(icon: "arrow.down.circle.fill", tint: OrdenTheme.accent, text: L10n.s("Si quieres IA: instala Ollama, ábrelo, y dale a Detectar otra vez.", "For local AI: install Ollama, launch it, and click Detect Again.")),
            .init(icon: "lock.fill", tint: .secondary, text: L10n.s("Todo es local en tu Mac. Findaro no sube tus archivos.", "100% on-device on your Mac. Findaro never uploads files."))
        ]
    }

    @ViewBuilder
    private var footer: some View {
        if ollama.available {
            OrdenDialogFooter(
                shortcutHint: "Local · :11434",
                cancelTitle: L10n.s("Seguir sin IA", "Continue without AI"),
                actionTitle: ollama.enabled ? L10n.s("Listo", "Done") : L10n.s("Activar Ollama", "Enable Ollama"),
                onCancel: {
                    browser.setOllamaEnabled(false)
                    browser.showOllamaSetupDialog = false
                    browser.appendAgentReply(
                        L10n.s("De acuerdo: sigo con atajos y reglas. Si más tarde quieres IA, abre Configurar Ollama.", "Understood: continuing with shortcuts and rules. Open Configure Ollama anytime.")
                    )
                },
                onAction: {
                    if !ollama.enabled {
                        browser.setOllamaEnabled(true)
                        browser.setOllamaModel(ollama.selectedModel)
                        browser.appendAgentReply(
                            L10n.s("Ollama activado con «\(ollama.selectedModel)». Ya puedo usar IA cuando esté corriendo.", "Ollama enabled with «\(ollama.selectedModel)». Ready to use local AI.")
                        )
                    }
                    browser.showOllamaSetupDialog = false
                }
            )
        } else {
            OrdenDialogFooter(
                shortcutHint: L10n.s("Opcional", "Optional"),
                cancelTitle: L10n.s("Cerrar", "Close"),
                actionTitle: L10n.s("Seguir sin IA", "Continue without AI"),
                onCancel: { browser.showOllamaSetupDialog = false },
                onAction: {
                    browser.setOllamaEnabled(false)
                    browser.showOllamaSetupDialog = false
                    browser.appendAgentReply(
                        L10n.s("Sin problema: trabajo con atajos y reglas. Cuando tengas Ollama, Configurar Ollama → Detectar.", "No problem: working with shortcuts and rules. When you have Ollama, click Detect Again.")
                    )
                }
            )
        }
    }

    private func detect() async {
        checking = true
        await ollama.probe()
        checking = false
    }

    private func openOllamaApp() {
        let app = URL(fileURLWithPath: "/Applications/Ollama.app")
        if FileManager.default.fileExists(atPath: app.path) {
            NSWorkspace.shared.open(app)
        } else if let url = URL(string: "https://ollama.com/download") {
            NSWorkspace.shared.open(url)
        }
    }
}

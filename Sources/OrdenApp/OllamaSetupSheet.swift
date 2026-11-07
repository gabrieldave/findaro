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
                title: "Inteligencia local (Ollama)",
                subtitle: "Opcional. Si no la quieres, el asistente sigue con atajos y reglas."
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                statusCard

                OrdenDialogSection(title: "Qué hace") {
                    Text("Con Ollama en este Mac, el asistente puede entender frases más libres. Todo queda en tu computadora: no se manda a la nube.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if ollama.available && !ollama.models.isEmpty {
                    OrdenDialogSection(title: "Modelo") {
                        Picker("Modelo", selection: Binding(
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
                        Label(checking ? "Detectando…" : "Detectar otra vez", systemImage: "arrow.clockwise")
                    }
                    .disabled(checking)

                    if !ollama.available {
                        Button("Abrir Ollama") {
                            openOllamaApp()
                        }
                        Button("Bajar Ollama…") {
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
        if checking { return "Buscando Ollama…" }
        if ollama.available {
            return ollama.enabled ? "Ollama listo y activado" : "Ollama detectado"
        }
        return "No encuentro Ollama"
    }

    private var statusDetail: String {
        if checking { return "Mirando http://127.0.0.1:11434" }
        if ollama.available {
            let n = ollama.models.count
            return n == 1
                ? "Hay 1 modelo instalado. Puedes activarlo abajo."
                : "Hay \(n) modelos. Elige uno y actívalo, o sigue sin IA."
        }
        return ollama.lastError
            ?? "No pasa nada: el asistente usa atajos y reglas. Si instalas Ollama después, vuelve a detectar."
    }

    private var hintRows: [OrdenDialogHintBox.Row] {
        if ollama.available {
            return [
                .init(icon: "checkmark.circle.fill", tint: .green, text: "Activar = el asistente usa el modelo cuando hace falta."),
                .init(icon: "checkmark.circle.fill", tint: .green, text: "Si Ollama se apaga, Findaro cae solo a reglas (no se rompe)."),
                .init(icon: "xmark.circle.fill", tint: .secondary, text: "No es obligatorio. Sin IA también funcionan atajos y búsquedas.")
            ]
        }
        return [
            .init(icon: "checkmark.circle.fill", tint: .green, text: "Sin Ollama: atajos (imágenes de hoy…) y frases sencillas siguen."),
            .init(icon: "arrow.down.circle.fill", tint: OrdenTheme.accent, text: "Si quieres IA: instala Ollama, ábrelo, y dale a Detectar otra vez."),
            .init(icon: "lock.fill", tint: .secondary, text: "Todo es local en tu Mac. Findaro no sube tus archivos.")
        ]
    }

    @ViewBuilder
    private var footer: some View {
        if ollama.available {
            OrdenDialogFooter(
                shortcutHint: "Local · :11434",
                cancelTitle: "Seguir sin IA",
                actionTitle: ollama.enabled ? "Listo" : "Activar Ollama",
                onCancel: {
                    browser.setOllamaEnabled(false)
                    browser.showOllamaSetupDialog = false
                    browser.appendAgentReply(
                        "De acuerdo: sigo con atajos y reglas. Si más tarde quieres IA, abre Configurar Ollama."
                    )
                },
                onAction: {
                    if !ollama.enabled {
                        browser.setOllamaEnabled(true)
                        browser.setOllamaModel(ollama.selectedModel)
                        browser.appendAgentReply(
                            "Ollama activado con «\(ollama.selectedModel)». Ya puedo usar IA cuando esté corriendo."
                        )
                    }
                    browser.showOllamaSetupDialog = false
                }
            )
        } else {
            OrdenDialogFooter(
                shortcutHint: "Opcional",
                cancelTitle: "Cerrar",
                actionTitle: "Seguir sin IA",
                onCancel: { browser.showOllamaSetupDialog = false },
                onAction: {
                    browser.setOllamaEnabled(false)
                    browser.showOllamaSetupDialog = false
                    browser.appendAgentReply(
                        "Sin problema: trabajo con atajos y reglas. Cuando tengas Ollama, Configurar Ollama → Detectar."
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

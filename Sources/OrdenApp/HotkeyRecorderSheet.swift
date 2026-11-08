import AppKit
import SwiftUI
import OrdenCore

struct HotkeyRecorderSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    let definition: AppHotkeyDefinition
    @Environment(\.dismiss) private var dismiss

    @State private var draft: KeyChord
    @State private var listening = true
    @State private var monitor: Any?
    @State private var showConflictAlert = false

    private var conflictingDefinition: AppHotkeyDefinition? {
        AppHotkeyCatalog.conflictingDefinition(
            for: draft,
            excludingId: definition.id,
            overrides: browser.keyboardHotkeyOverrides
        )
    }

    init(definition: AppHotkeyDefinition, current: KeyChord) {
        self.definition = definition
        _draft = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(definition.title)
                .font(.title2.weight(.semibold))
            Text(definition.detail)
                .foregroundStyle(.secondary)

            HStack {
                Text(draft.displayLabel)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospaced())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let conflict = conflictingDefinition {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conflicto: Ya asignado a «\(conflict.title)» (\(conflict.group.titleSpanish))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("No se sobrescribirá en silencio. Guardar requerirá confirmar la reasignación.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(listening ? "Pulsa la nueva combinación…" : "Combinación capturada")
                .font(.caption)
                .foregroundStyle(listening ? OrdenTheme.accent : .secondary)

            HStack {
                Button("Restablecer") {
                    draft = definition.defaultChord
                    listening = false
                }
                .disabled(draft == definition.defaultChord)

                Spacer()

                Button("Cancelar") { dismiss() }
                Button("Guardar") {
                    if conflictingDefinition != nil {
                        showConflictAlert = true
                    } else {
                        browser.setKeyboardHotkey(definition.id, chord: draft)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(conflictingDefinition != nil ? .orange : OrdenTheme.accent)
                .disabled(!definition.isEditable)
            }
        }
        .padding(24)
        .frame(width: 420)
        .alert("Conflicto de atajo de teclado", isPresented: $showConflictAlert) {
            Button("Reasignar", role: .destructive) {
                if let conflict = conflictingDefinition {
                    browser.resetKeyboardHotkey(conflict.id)
                }
                browser.setKeyboardHotkey(definition.id, chord: draft)
                dismiss()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            if let conflict = conflictingDefinition {
                Text("La combinación «\(draft.displayLabel)» ya está en uso por «\(conflict.title)». ¿Deseas reasignarla a «\(definition.title)»?")
            } else {
                Text("Esta combinación ya pertenece a otra acción.")
            }
        }
        .onAppear { startMonitor() }
        .onDisappear { stopMonitor() }
    }

    private func startMonitor() {
        stopMonitor()
        guard definition.isEditable else {
            listening = false
            return
        }
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancela captura, no asigna Esc salvo que sea el default intent
                listening = false
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
            // Ignorar modificadores solos
            if [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(event.keyCode) {
                return nil
            }
            draft = KeyChord(
                keyCode: event.keyCode,
                character: chars,
                command: flags.contains(.command),
                option: flags.contains(.option),
                shift: flags.contains(.shift),
                control: flags.contains(.control)
            )
            listening = false
            return nil
        }
    }

    private func stopMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

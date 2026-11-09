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
            Text(definition.titleLocalized)
                .font(.title2.weight(.semibold))
            Text(definition.detailLocalized)
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
                        Text(L10n.s("Conflicto: Ya asignado a «\(conflict.titleLocalized)» (\(conflict.group.titleLocalized))", "Conflict: Already assigned to «\(conflict.titleLocalized)» (\(conflict.group.titleLocalized))"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(L10n.s("No se sobrescribirá en silencio. Guardar requerirá confirmar la reasignación.", "Will not be silently overwritten. Saving will require confirming re-assignment."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(listening ? L10n.s("Pulsa la nueva combinación…", "Press new keyboard combination…") : L10n.s("Combinación capturada", "Combination captured"))
                .font(.caption)
                .foregroundStyle(listening ? OrdenTheme.accent : .secondary)

            HStack {
                Button(L10n.s("Restablecer", "Reset")) {
                    draft = definition.defaultChord
                    listening = false
                }
                .disabled(draft == definition.defaultChord)

                Spacer()

                Button(L10n.s("Cancelar", "Cancel")) { dismiss() }
                Button(L10n.s("Guardar", "Save")) {
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
        .alert(L10n.s("Conflicto de atajo de teclado", "Keyboard Shortcut Conflict"), isPresented: $showConflictAlert) {
            Button(L10n.s("Reasignar", "Reassign"), role: .destructive) {
                if let conflict = conflictingDefinition {
                    browser.resetKeyboardHotkey(conflict.id)
                }
                browser.setKeyboardHotkey(definition.id, chord: draft)
                dismiss()
            }
            Button(L10n.s("Cancelar", "Cancel"), role: .cancel) { }
        } message: {
            if let conflict = conflictingDefinition {
                Text(L10n.s("La combinación «\(draft.displayLabel)» ya está en uso por «\(conflict.titleLocalized)». ¿Deseas reasignarla a «\(definition.titleLocalized)»?", "The key combination «\(draft.displayLabel)» is already used by «\(conflict.titleLocalized)». Do you want to reassign it to «\(definition.titleLocalized)»?"))
            } else {
                Text(L10n.s("Esta combinación ya pertenece a otra acción.", "This combination already belongs to another action."))
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

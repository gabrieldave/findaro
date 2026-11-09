import SwiftUI
import OrdenCore

/// Crear o editar un atajo del asistente (tipo + fechas + nombre).
struct ShortcutEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var existing: AssistantShortcut?
    var onSave: (AssistantShortcut) -> Void

    @State private var title = ""
    @State private var kind: Kind = .images
    @State private var window: WindowChoice = .today
    @State private var customDays: Int = 7

    enum Kind: String, CaseIterable, Identifiable {
        case images, documents, audio, video, pdf, any
        var id: String { rawValue }
        var label: String {
            switch self {
            case .images: return L10n.s("Imágenes", "Images")
            case .documents: return L10n.s("Documentos", "Documents")
            case .audio: return L10n.s("Música / audio", "Music / Audio")
            case .video: return L10n.s("Vídeos", "Videos")
            case .pdf: return "PDF"
            case .any: return L10n.s("Cualquier tipo", "Any type")
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

        static func from(categories: [FileCategory]) -> Kind {
            if categories == AssistantShortcut.documentCategories { return .documents }
            if categories == [.image] { return .images }
            if categories == [.audio] { return .audio }
            if categories == [.video] { return .video }
            if categories == [.pdf] { return .pdf }
            if categories.isEmpty { return .any }
            return .any
        }
    }

    enum WindowChoice: String, CaseIterable, Identifiable {
        case today, yesterday, days3, days7, days30, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return L10n.s("Hoy", "Today")
            case .yesterday: return L10n.s("Ayer", "Yesterday")
            case .days3: return L10n.s("Últimos 3 días", "Last 3 days")
            case .days7: return L10n.s("Última semana", "Last week")
            case .days30: return L10n.s("Últimos 30 días", "Last 30 days")
            case .custom: return L10n.s("Personalizado…", "Custom…")
            }
        }

        func dateWindow(customDays: Int) -> ShortcutDateWindow {
            switch self {
            case .today: return .today
            case .yesterday: return .yesterday
            case .days3: return .lastDays(3)
            case .days7: return .lastDays(7)
            case .days30: return .lastDays(30)
            case .custom: return .lastDays(max(1, min(365, customDays)))
            }
        }

        static func from(_ window: ShortcutDateWindow) -> (WindowChoice, Int) {
            switch window {
            case .today: return (.today, 7)
            case .yesterday: return (.yesterday, 7)
            case .lastDays(let n):
                switch n {
                case 3: return (.days3, 3)
                case 7: return (.days7, 7)
                case 30: return (.days30, 30)
                default: return (.custom, n)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? L10n.s("Nuevo atajo", "New Shortcut") : L10n.s("Editar atajo", "Edit Shortcut"))
                .font(.title2.weight(.semibold))
            Text(L10n.s("Nombre, tipo de archivo y rango de fechas. Queda en el asistente y en Ajustes → Atajos.", "Name, file type, and date range. Available in assistant and in Settings → Shortcuts."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(L10n.s("Nombre", "Name"), text: $title)
                .textFieldStyle(.roundedBorder)

            Picker(L10n.s("Tipo", "Type"), selection: $kind) {
                ForEach(Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            Picker(L10n.s("Cuándo", "When"), selection: $window) {
                ForEach(WindowChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)

            if window == .custom {
                Stepper(value: $customDays, in: 1...365) {
                    Text(L10n.s("Últimos \(customDays) días", "Last \(customDays) days"))
                }
            }

            HStack {
                Button(L10n.s("Cancelar", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existing == nil ? L10n.s("Crear", "Create") : L10n.s("Guardar", "Save")) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let existing else { return }
        title = existing.title
        kind = Kind.from(categories: existing.categories)
        let mapped = WindowChoice.from(existing.dateWindow)
        window = mapped.0
        customDays = mapped.1
    }

    private func save() {
        let win = window.dateWindow(customDays: customDays)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let auto: String
        if kind == .documents {
            auto = L10n.s("Documentos \(win.labelSpanish)", "Documents \(win.labelEnglish)")
        } else if kind == .any {
            auto = L10n.s("Archivos \(win.labelSpanish)", "Files \(win.labelEnglish)")
        } else {
            auto = "\(kind.label) \(win.labelLocalized)"
        }
        let shortcut = AssistantShortcut(
            id: existing?.id ?? UUID(),
            title: name.isEmpty ? auto : name,
            categories: kind.categories,
            dateWindow: win,
            createdAt: existing?.createdAt ?? Date()
        )
        onSave(shortcut)
        dismiss()
    }
}

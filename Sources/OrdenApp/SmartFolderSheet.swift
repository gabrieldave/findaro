import SwiftUI
import AppKit
import OrdenCore

/// Crear / editar una carpeta inteligente (búsqueda guardada en Favoritos).
/// Edita una copia local; solo al pulsar Guardar se escribe en preferencias.
struct SmartFolderSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    @State private var draft: SmartFolder
    @State private var extensionsText: String
    @State private var errorText: String?
    @State private var previewCount: Int?
    @FocusState private var nameFocused: Bool
    let isNew: Bool

    /// Tipos que tiene sentido elegir (sin «Carpeta» ni «Otro»).
    private static let pickableCategories: [FileCategory] = [
        .image, .pdf, .video, .audio, .archive, .word, .excel, .powerpoint, .text, .code, .diskImage, .app
    ]

    private enum DateChoice: String, CaseIterable, Identifiable {
        case any, today, yesterday, week, month
        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: return L10n.s("Cualquiera", "Any")
            case .today: return L10n.s("Hoy", "Today")
            case .yesterday: return L10n.s("Ayer", "Yesterday")
            case .week: return L10n.s("7 días", "7 days")
            case .month: return L10n.s("30 días", "30 days")
            }
        }

        var window: ShortcutDateWindow? {
            switch self {
            case .any: return nil
            case .today: return .today
            case .yesterday: return .yesterday
            case .week: return .lastDays(7)
            case .month: return .lastDays(30)
            }
        }

        static func from(_ window: ShortcutDateWindow?) -> DateChoice {
            guard let window else { return .any }
            switch window {
            case .today: return .today
            case .yesterday: return .yesterday
            case .lastDays(let n):
                if n <= 1 { return .today }
                if n <= 7 { return .week }
                return .month
            }
        }
    }

    init(initial: SmartFolder, isNew: Bool) {
        _draft = State(initialValue: initial)
        _extensionsText = State(initialValue: initial.extensionsText)
        self.isNew = isNew
    }

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "folder.badge.gearshape",
                title: isNew
                    ? L10n.s("Nueva carpeta inteligente", "New Smart Folder")
                    : L10n.s("Editar carpeta inteligente", "Edit Smart Folder"),
                subtitle: L10n.s(
                    "Una búsqueda guardada en Favoritos. Un clic y ves solo esos archivos. No mueve ni copia nada.",
                    "A saved search in Favorites. One click shows only those files. Nothing is moved or copied."
                )
            )
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isNew {
                        presetsSection
                    }
                    nameSection
                    placeSection
                    typeSection
                    extensionsSection
                    nameContainsSection
                    dateSection
                    summarySection
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(OrdenTheme.danger)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 520)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: nil,
                cancelTitle: L10n.s("Cancelar", "Cancel"),
                actionTitle: isNew
                    ? L10n.s("Crear y abrir", "Create & Open")
                    : L10n.s("Guardar", "Save"),
                actionDisabled: !draft.hasCriteria,
                onCancel: { browser.cancelSmartFolderDraft() },
                onAction: save
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                nameFocused = true
            }
        }
        .task(id: draft) {
            // Cuenta rápida (primer nivel) tras una pausa corta al escribir.
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            previewCount = browser.smartFolderPreviewCount(draft)
        }
    }

    // MARK: - Secciones

    private var presetsSection: some View {
        OrdenDialogSection(title: L10n.s("Empieza rápido", "Quick start")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(SmartFolder.Preset.allCases, id: \.self) { preset in
                    Button {
                        draft = preset.apply(to: draft)
                        extensionsText = draft.extensionsText
                        errorText = nil
                    } label: {
                        Label(preset.titleLocalized, systemImage: preset.symbolName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var nameSection: some View {
        OrdenDialogSection(title: L10n.s("Nombre en Favoritos", "Name in Favorites")) {
            TextField(draft.hasCriteria ? draft.suggestedName : L10n.s("Ej. Mis PDF", "e.g. My PDFs"), text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(save)
        }
    }

    private var placeSection: some View {
        OrdenDialogSection(title: L10n.s("Buscar en", "Look in")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(OrdenTheme.accent)
                    Text(OrdenPathDisplay.short(draft.rootPath))
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(draft.rootPath)
                    Spacer(minLength: 4)
                    Menu {
                        Button(L10n.s("Carpeta actual", "Current folder")) {
                            draft.rootPath = browser.currentPath
                        }
                        Button(L10n.s("Descargas", "Downloads")) {
                            draft.rootPath = homeChild("Downloads")
                        }
                        Button(L10n.s("Escritorio", "Desktop")) {
                            draft.rootPath = homeChild("Desktop")
                        }
                        Button(L10n.s("Documentos", "Documents")) {
                            draft.rootPath = homeChild("Documents")
                        }
                        Button(L10n.s("Mi carpeta de inicio", "My home folder")) {
                            draft.rootPath = FileManager.default.homeDirectoryForCurrentUser.path
                        }
                        Divider()
                        Button(L10n.s("Elegir otra…", "Choose another…")) {
                            pickFolder()
                        }
                    } label: {
                        Text(L10n.s("Cambiar", "Change"))
                    }
                    .menuStyle(.borderedButton)
                    .fixedSize()
                }
                Toggle(isOn: $draft.includeSubfolders) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.s("Incluir subcarpetas", "Include subfolders"))
                        Text(L10n.s(
                            "Busca también dentro de todas las carpetas de adentro.",
                            "Also looks inside every folder within."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var typeSection: some View {
        OrdenDialogSection(title: L10n.s("Tipo de archivo", "File type")) {
            VStack(alignment: .leading, spacing: 6) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(Self.pickableCategories, id: \.self) { category in
                        categoryChip(category)
                    }
                }
                Text(L10n.s("Sin marcar = cualquier tipo.", "None selected = any type."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func categoryChip(_ category: FileCategory) -> some View {
        let on = draft.categories.contains(category)
        let tint = Color(hex: category.tintHex)
        return Button {
            if on {
                draft.categories.removeAll { $0 == category }
            } else {
                draft.categories.append(category)
            }
            errorText = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : category.symbolName)
                    .foregroundStyle(on ? .white : tint)
                    .frame(width: 16)
                Text(category.labelLocalized)
                    .lineLimit(1)
                    .foregroundStyle(on ? .white : .primary)
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                on ? tint.opacity(0.85) : OrdenTheme.panelFill,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(on ? Color.clear : OrdenTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var extensionsSection: some View {
        OrdenDialogSection(title: L10n.s("Extensiones (opcional)", "Extensions (optional)")) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(L10n.s("Ej. zip, rar, 7z", "e.g. zip, rar, 7z"), text: $extensionsText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: extensionsText) { _, newValue in
                        draft.extensions = SmartFolder.parseExtensions(newValue)
                        errorText = nil
                    }
                Text(L10n.s(
                    "Cualquier extensión, separadas por coma. Se suman a los tipos marcados.",
                    "Any extension, comma-separated. Added to the types selected above."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var nameContainsSection: some View {
        OrdenDialogSection(title: L10n.s("El nombre contiene (opcional)", "Name contains (optional)")) {
            TextField(L10n.s("Ej. factura", "e.g. invoice"), text: $draft.nameContains)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
        }
    }

    private var dateSection: some View {
        OrdenDialogSection(title: L10n.s("Agregado o descargado", "Added or downloaded")) {
            Picker("", selection: Binding(
                get: { DateChoice.from(draft.dateWindow) },
                set: { draft.dateWindow = $0.window; errorText = nil }
            )) {
                ForEach(DateChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var summarySection: some View {
        var rows: [OrdenDialogHintBox.Row] = []
        if draft.hasCriteria {
            rows.append(.init(icon: draft.symbolName, tint: Color(hex: draft.tintHex), text: draft.summaryLocalized))
            if let previewCount {
                let text: String
                if draft.includeSubfolders {
                    text = L10n.s(
                        "Ahora mismo: \(previewCount) en el primer nivel (más las de subcarpetas).",
                        "Right now: \(previewCount) at the top level (plus those in subfolders)."
                    )
                } else {
                    text = previewCount == 1
                        ? L10n.s("Ahora mismo: 1 archivo coincide.", "Right now: 1 file matches.")
                        : L10n.s("Ahora mismo: \(previewCount) archivos coinciden.", "Right now: \(previewCount) files match.")
                }
                rows.append(.init(icon: "number.circle.fill", tint: OrdenTheme.accent, text: text))
            }
            rows.append(.init(
                icon: "arrow.triangle.2.circlepath",
                tint: .green,
                text: L10n.s(
                    "Se actualiza sola: los archivos nuevos que cumplan la regla aparecen al abrirla.",
                    "Always up to date: new matching files show up when you open it."
                )
            ))
        } else {
            rows.append(.init(
                icon: "hand.point.up.left.fill",
                tint: .orange,
                text: L10n.s(
                    "Elige al menos un tipo, una extensión, un texto o una fecha.",
                    "Pick at least one type, extension, text or date."
                )
            ))
        }
        return OrdenDialogHintBox(rows: rows)
    }

    // MARK: - Acciones

    private func save() {
        guard draft.hasCriteria else {
            errorText = L10n.s(
                "Elige al menos un tipo, una extensión, un texto o una fecha.",
                "Pick at least one type, extension, text or date."
            )
            return
        }
        draft.extensions = SmartFolder.parseExtensions(extensionsText)
        browser.smartFolderDraft = draft
        errorText = browser.saveSmartFolderDraft(open: true)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: draft.rootPath)
        panel.message = L10n.s("¿Dónde busca esta carpeta inteligente?", "Where should this smart folder look?")
        panel.prompt = L10n.s("Elegir", "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.rootPath = url.path
    }

    private func homeChild(_ name: String) -> String {
        (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(name)
    }
}

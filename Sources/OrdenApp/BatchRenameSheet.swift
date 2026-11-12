import SwiftUI
import OrdenCore

struct BatchRenameSheet: View {
    @EnvironmentObject private var browser: BrowserModel

    enum Mode: String, CaseIterable, Identifiable {
        case replace
        case sequential
        case affix
        case changeCase
        case regex

        var id: String { rawValue }

        var title: String {
            switch self {
            case .replace: return L10n.s("Reemplazar", "Replace")
            case .sequential: return L10n.s("Secuencia", "Sequence")
            case .affix: return L10n.s("Prefijo / Sufijo", "Prefix / Suffix")
            case .changeCase: return L10n.s("Mayúsculas", "Case")
            case .regex: return "Regex"
            }
        }
    }

    @State private var mode: Mode = .replace
    @State private var findText: String = ""
    @State private var replaceText: String = ""
    @State private var caseSensitive: Bool = false

    @State private var baseName: String = ""
    @State private var startAt: Int = 1
    @State private var paddingDigits: Int = 3
    @State private var separator: String = "_"

    @State private var prefixText: String = ""
    @State private var suffixText: String = ""

    @State private var caseStyle: BatchRenameCaseStyle = .lowercase

    @State private var regexPattern: String = ""
    @State private var regexTemplate: String = ""

    private let engine = BatchRenameEngine()

    private var activeRules: [BatchRenameRule] {
        switch mode {
        case .replace:
            return [.replaceText(find: findText, replace: replaceText, caseSensitive: caseSensitive)]
        case .sequential:
            return [.sequential(baseName: baseName, startAt: startAt, paddingDigits: paddingDigits, separator: separator)]
        case .affix:
            return [.addAffix(prefix: prefixText, suffix: suffixText)]
        case .changeCase:
            return [.changeCase(caseStyle)]
        case .regex:
            return [.regexReplace(pattern: regexPattern, template: regexTemplate)]
        }
    }

    private var previewItems: [BatchRenamePreviewItem] {
        let urls = browser.batchRenameTargetEntries.map { URL(fileURLWithPath: $0.path) }
        return engine.preview(urls: urls, rules: activeRules)
    }

    private var actionableCount: Int {
        previewItems.filter(\.canApply).count
    }

    private var conflictCount: Int {
        previewItems.filter { $0.conflict != nil }.count
    }

    private var canCommit: Bool {
        actionableCount > 0 && conflictCount == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            modeSelector
            controlsCard
            previewTable
            footer
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .background(OrdenTheme.windowFill)
        .onAppear {
            browser.batchRenameDraftPreview = previewItems
        }
        .onChange(of: previewItems) { _, newItems in
            browser.batchRenameDraftPreview = newItems
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.title2.weight(.semibold))
                .foregroundStyle(OrdenTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.s("Renombrado masivo Pro", "Batch Rename Pro"))
                    .font(.title3.weight(.bold))
                Text(
                    L10n.s(
                        "\(browser.batchRenameTargetEntries.count) elementos seleccionados · Las extensiones se conservan automáticamente",
                        "\(browser.batchRenameTargetEntries.count) items selected · File extensions are preserved automatically"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var modeSelector: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch mode {
            case .replace:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Buscar", "Find")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField(L10n.s("Texto a buscar…", "Text to find…"), text: $findText)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Reemplazar con", "Replace with")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField(L10n.s("Texto nuevo (vacío = borrar)", "Replacement (empty = remove)"), text: $replaceText)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                Toggle(L10n.s("Distinguir mayúsculas y minúsculas", "Case sensitive"), isOn: $caseSensitive)
                    .font(.caption)

            case .sequential:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Nombre base (vacío = conservar actual)", "Base name (empty = keep current)"))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("photo / factura / clip", text: $baseName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Separador", "Separator")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("_", text: $separator)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                    }
                    Stepper(value: $startAt, in: 0...99999) {
                        Text("\(L10n.s("Inicio", "Start")): \(startAt)").font(.caption.monospacedDigit())
                    }
                    Stepper(value: $paddingDigits, in: 1...6) {
                        Text("\(L10n.s("Dígitos", "Digits")): \(paddingDigits)").font(.caption.monospacedDigit())
                    }
                }

            case .affix:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Prefijo", "Prefix")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("2026_", text: $prefixText)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Sufijo (antes de la extensión)", "Suffix (before extension)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("_final", text: $suffixText)
                            .textFieldStyle(.roundedBorder)
                    }
                }

            case .changeCase:
                Picker(L10n.s("Formato", "Format"), selection: $caseStyle) {
                    Text(L10n.s("minúsculas", "lowercase")).tag(BatchRenameCaseStyle.lowercase)
                    Text(L10n.s("MAYÚSCULAS", "UPPERCASE")).tag(BatchRenameCaseStyle.uppercase)
                    Text(L10n.s("Tipo Título", "Title Case")).tag(BatchRenameCaseStyle.titleCase)
                }
                .pickerStyle(.segmented)

            case .regex:
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Patrón Regex", "Regex Pattern")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("^IMG_(\\d+)", text: $regexPattern)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Plantilla ($1, $2…)", "Template ($1, $2…)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("Foto_$1", text: $regexTemplate)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .padding(12)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
        )
    }

    private var previewTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.s("Nombre actual", "Current Name"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.s("Nombre nuevo", "New Name"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OrdenTheme.elevatedFill.opacity(0.6))

            Divider().opacity(0.35)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(previewItems) { item in
                        HStack(spacing: 10) {
                            Text(item.originalName)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            HStack(spacing: 6) {
                                Text(item.proposedName.isEmpty ? "—" : item.proposedName)
                                    .font(.system(.callout, design: .monospaced).weight(item.hasChanges ? .semibold : .regular))
                                    .foregroundStyle(
                                        item.conflict != nil
                                            ? Color.red
                                            : (item.hasChanges ? OrdenTheme.accent : Color.secondary)
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if let conflict = item.conflict {
                                    Text(conflictLabel(conflict))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.18), in: Capsule())
                                        .foregroundStyle(.red)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        Divider().opacity(0.2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack {
            if conflictCount > 0 {
                Label(
                    L10n.s("\(conflictCount) conflicto(s) detectados", "\(conflictCount) conflict(s) detected"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            } else {
                Text(
                    L10n.s(
                        "\(actionableCount) cambio(s) listos · Transaccional en 2 fases (⌘Z deshace)",
                        "\(actionableCount) change(s) ready · Two-phase transactional (⌘Z undoes)"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(L10n.s("Cancelar", "Cancel")) {
                browser.cancelBatchRename()
            }
            .keyboardShortcut(.cancelAction)

            Button(L10n.s("Renombrar \(actionableCount)", "Rename \(actionableCount)")) {
                browser.batchRenameDraftPreview = previewItems
                browser.commitBatchRename()
            }
            .buttonStyle(.borderedProminent)
            .tint(OrdenTheme.accent)
            .disabled(!canCommit)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func conflictLabel(_ conflict: BatchRenameConflict) -> String {
        switch conflict {
        case .emptyName: return L10n.s("Vacío", "Empty")
        case .invalidCharacters: return L10n.s("Carácter inválido", "Invalid char")
        case .duplicateInBatch: return L10n.s("Duplicado", "Duplicate")
        case .alreadyExistsOnDisk: return L10n.s("Ya existe", "Exists")
        case .invalidRegex: return L10n.s("Regex inválido", "Bad regex")
        }
    }
}

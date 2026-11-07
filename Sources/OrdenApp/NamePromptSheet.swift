import SwiftUI

/// Nueva carpeta / nuevo archivo / renombrar — chrome formal compartido.
enum NamePromptKind {
    case newFolder
    case newFile
    case rename

    var systemImage: String {
        switch self {
        case .newFolder: return "folder.badge.plus"
        case .newFile: return "doc.badge.plus"
        case .rename: return "pencil"
        }
    }

    var title: String {
        switch self {
        case .newFolder: return "Nueva carpeta"
        case .newFile: return "Nuevo archivo"
        case .rename: return "Renombrar"
        }
    }

    var subtitle: String {
        switch self {
        case .newFolder: return "Se crea dentro de la carpeta actual"
        case .newFile: return "Archivo vacío en la carpeta actual"
        case .rename: return "Cambia el nombre del elemento seleccionado"
        }
    }

    var fieldTitle: String {
        switch self {
        case .newFolder: return "Nombre de la carpeta"
        case .newFile: return "Nombre del archivo"
        case .rename: return "Nuevo nombre"
        }
    }

    var placeholder: String {
        switch self {
        case .newFolder: return "Carpeta sin título"
        case .newFile: return "Sin título.txt"
        case .rename: return "Nombre"
        }
    }

    var actionTitle: String {
        switch self {
        case .newFolder, .newFile: return "Crear"
        case .rename: return "Guardar"
        }
    }

    var shortcutHint: String? {
        switch self {
        case .newFolder: return "Atajo ⇧⌘N"
        case .newFile: return "Atajo ⌘N"
        case .rename: return nil
        }
    }
}

struct NamePromptSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    let kind: NamePromptKind
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: kind.systemImage,
                title: kind.title,
                subtitle: kind.subtitle
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                OrdenDialogSection(title: "Ubicación") {
                    Text(OrdenPathDisplay.short(browser.currentPath))
                        .font(.body.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                OrdenDialogSection(title: kind.fieldTitle) {
                    TextField(kind.placeholder, text: $browser.nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onSubmit { commit() }
                    hintText
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                OrdenDialogHintBox(rows: hintRows)
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: kind.shortcutHint,
                cancelTitle: "Cancelar",
                actionTitle: kind.actionTitle,
                actionDisabled: browser.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: cancel,
                onAction: commit
            )
        }
        .onAppear {
            fieldFocused = true
            DispatchQueue.main.async { fieldFocused = true }
        }
    }

    @ViewBuilder
    private var hintText: some View {
        switch kind {
        case .newFolder:
            Text("Si el nombre ya existe, Ordena añade un número automáticamente.")
        case .newFile:
            Text("Sin extensión se usa .txt. Puedes poner .md, .json, .csv, etc.")
        case .rename:
            Text("Mantén la extensión si quieres conservar el tipo de archivo.")
        }
    }

    private var hintRows: [OrdenDialogHintBox.Row] {
        switch kind {
        case .newFolder:
            return [
                .init(icon: "checkmark.circle.fill", tint: .green, text: "La carpeta nueva queda seleccionada al crearla."),
                .init(icon: "xmark.circle.fill", tint: .secondary, text: "No uses barras / en el nombre.")
            ]
        case .newFile:
            return [
                .init(icon: "checkmark.circle.fill", tint: .green, text: "Se crea vacío; luego puedes abrirlo con otra app."),
                .init(icon: "info.circle.fill", tint: OrdenTheme.accent, text: "La búsqueda por contenido llegará con el asistente / IA local.")
            ]
        case .rename:
            return [
                .init(icon: "checkmark.circle.fill", tint: .green, text: "Solo cambia el nombre; la ubicación se mantiene."),
                .init(icon: "xmark.circle.fill", tint: .secondary, text: "No puede coincidir con otro nombre ya usado aquí.")
            ]
        }
    }

    private func cancel() {
        switch kind {
        case .newFolder: browser.showNewFolderDialog = false
        case .newFile: browser.showNewFileDialog = false
        case .rename:
            browser.showRenameDialog = false
            browser.renameTargetPath = nil
        }
    }

    private func commit() {
        switch kind {
        case .newFolder:
            browser.createFolderFromDraft()
            browser.showNewFolderDialog = false
        case .newFile:
            browser.createFileFromDraft()
            browser.showNewFileDialog = false
        case .rename:
            browser.commitRenameFromDraft()
            browser.showRenameDialog = false
        }
    }
}

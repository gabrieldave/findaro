import SwiftUI
import OrdenCore

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
        case .newFolder: return L10n.s("Nueva carpeta", "New Folder")
        case .newFile: return L10n.s("Nuevo archivo", "New File")
        case .rename: return L10n.s("Renombrar", "Rename")
        }
    }

    var subtitle: String {
        switch self {
        case .newFolder: return L10n.s("Se crea dentro de la carpeta actual", "Created inside the current folder")
        case .newFile: return L10n.s("Archivo vacío en la carpeta actual", "Empty file inside the current folder")
        case .rename: return L10n.s("Solo el nombre; la extensión se conserva", "Name only; extension is kept")
        }
    }

    var fieldTitle: String {
        switch self {
        case .newFolder: return L10n.s("Nombre de la carpeta", "Folder Name")
        case .newFile: return L10n.s("Nombre del archivo", "File Name")
        case .rename: return L10n.s("Nuevo nombre", "New Name")
        }
    }

    var placeholder: String {
        switch self {
        case .newFolder: return L10n.s("Carpeta sin título", "Untitled Folder")
        case .newFile: return L10n.s("Sin título.txt", "Untitled.txt")
        case .rename: return L10n.s("Nombre", "Name")
        }
    }

    var actionTitle: String {
        switch self {
        case .newFolder, .newFile: return L10n.s("Crear", "Create")
        case .rename: return L10n.s("Guardar", "Save")
        }
    }

    var shortcutHint: String? {
        switch self {
        case .newFolder: return L10n.s("Atajo ⇧⌘N", "Shortcut ⇧⌘N")
        case .newFile: return L10n.s("Atajo ⌘N", "Shortcut ⌘N")
        case .rename: return L10n.s("Atajo ⌃R · F2", "Shortcut ⌃R · F2")
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
                OrdenDialogSection(title: L10n.s("Ubicación", "Location")) {
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
                cancelTitle: L10n.s("Cancelar", "Cancel"),
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
            Text(L10n.s("Si el nombre ya existe, Findaro añade un número automáticamente.", "If the name exists, Findaro adds a number automatically."))
        case .newFile:
            Text(L10n.s("Sin extensión se usa .txt. Puedes poner .md, .json, .csv, etc.", "Without extension, .txt is used. You can enter .md, .json, .csv, etc."))
        case .rename:
            if let ext = browser.renamePreservedExtension, !ext.isEmpty {
                Text(L10n.s("Se conserva automáticamente «.\(ext)».", "«.\(ext)» is kept automatically."))
            } else {
                Text(L10n.s("Carpeta o sin extensión: editas el nombre completo.", "Folder or no extension: edit the full name."))
            }
        }
    }

    private var hintRows: [OrdenDialogHintBox.Row] {
        switch kind {
        case .newFolder:
            return [
                .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("La carpeta nueva queda seleccionada al crearla.", "The new folder is selected once created.")),
                .init(icon: "xmark.circle.fill", tint: .secondary, text: L10n.s("No uses barras / en el nombre.", "Do not use forward slashes / in the name."))
            ]
        case .newFile:
            return [
                .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("Se crea vacío; luego puedes abrirlo con otra app.", "Created empty; you can open it with another app.")),
                .init(icon: "info.circle.fill", tint: OrdenTheme.accent, text: L10n.s("La búsqueda por contenido funciona con el asistente local.", "Content search works with the local assistant."))
            ]
        case .rename:
            return [
                .init(icon: "checkmark.circle.fill", tint: .green, text: L10n.s("Solo cambia el nombre; la extensión y la ubicación se mantienen.", "Only the name changes; extension and location stay.")),
                .init(icon: "xmark.circle.fill", tint: .secondary, text: L10n.s("No puede coincidir con otro nombre ya usado aquí.", "Cannot match an existing name in this folder."))
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
            browser.renamePreservedExtension = nil
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

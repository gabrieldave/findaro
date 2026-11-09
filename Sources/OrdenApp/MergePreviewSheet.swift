import SwiftUI
import OrdenCore

struct MergePreviewSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    let preview: FolderMerge.Preview

    private var asMove: Bool { browser.pendingMergeMove }

    var body: some View {
        OrdenDialogShell {
            OrdenDialogHeader(
                systemImage: "folder.badge.plus",
                title: L10n.s("Fusionar carpetas", "Smart Merge Folders"),
                subtitle: "«\(URL(fileURLWithPath: preview.sourcePath).lastPathComponent)» → «\(URL(fileURLWithPath: preview.destPath).lastPathComponent)»"
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    labeled(L10n.s("Nuevos", "New"), preview.onlySourceCount, .green)
                    labeled(L10n.s("Iguales", "Identical"), preview.identicalCount, .secondary)
                    labeled(L10n.s("Distintos", "Conflicts"), preview.conflictCount, .orange)
                }

                OrdenDialogHintBox(rows: [
                    .init(
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        text: L10n.s("Los nuevos siempre se copian. Los iguales no se tocan.", "New files are copied. Identical files remain untouched.")
                    ),
                    .init(
                        icon: "doc.on.doc",
                        tint: OrdenTheme.accent,
                        text: L10n.s("Conservar ambos: los que chocan se guardan como «nombre 2».", "Keep both: conflicting files are saved as «filename 2».")
                    ),
                    .init(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: L10n.s("Reemplazar: el archivo anterior se conserva en la Papelera para intentar restaurarlo con ⌘Z.", "Replace: previous file is moved safely to macOS Trash.")
                    ),
                    .init(
                        icon: asMove ? "trash" : "info.circle.fill",
                        tint: asMove ? .orange : .secondary,
                        text: asMove
                            ? L10n.s("Si eliges mover, la carpeta de origen va a la Papelera al confirmar.", "If moving, source folder is moved to Trash upon confirmation.")
                            : L10n.s("⌘Z deshace bien la opción «conservar ambos»; con reemplazo el archivo viejo va a la Papelera.", "⌘Z cleanly undos «keep both»; with replace older file is moved to Trash.")
                    )
                ])

                if preview.items.isEmpty {
                    Text(asMove
                        ? L10n.s("Todo coincide. El origen solo se enviará a la Papelera después de verificarlo otra vez.", "Everything matches. Source will be moved to Trash after verification.")
                        : L10n.s("No hay diferencias que fusionar.", "No differences to merge."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List(preview.items.prefix(80)) { item in
                        HStack {
                            Text(item.relativePath)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(label(for: item.kind))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(color(for: item.kind))
                        }
                    }
                    .frame(minHeight: 180)
                    if preview.items.count > 80 {
                        Text(L10n.s("Mostrando 80 de \(preview.items.count) elementos.", "Showing 80 of \(preview.items.count) items."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        } footer: {
            HStack(spacing: 10) {
                Button(L10n.s("Cancelar", "Cancel")) { browser.cancelPendingMerge() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.s("Conservar ambos", "Keep both")) {
                    browser.confirmPendingMerge(overwriteConflicts: false)
                }
                .keyboardShortcut(.defaultAction)
                .help(L10n.s("Conflictos → nombre 2 · Enter", "Conflicts → filename 2 · Enter"))
                Button(asMove ? L10n.s("Reemplazar y mover", "Replace & Move") : L10n.s("Reemplazar conflictos", "Replace Conflicts")) {
                    browser.confirmPendingMerge(overwriteConflicts: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help(L10n.s("El que traes pisa al del destino", "Incoming files overwrite destination"))
                .disabled(preview.conflictCount == 0 && preview.onlySourceCount == 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 580)
    }

    private func labeled(_ title: String, _ n: Int, _ color: Color) -> some View {
        VStack {
            Text("\(n)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func label(for kind: FolderMerge.ItemKind) -> String {
        switch kind {
        case .onlySource: return L10n.s("nuevo", "new")
        case .onlyDest: return L10n.s("solo destino", "destination only")
        case .identical: return L10n.s("igual", "identical")
        case .different: return L10n.s("conflicto", "conflict")
        }
    }

    private func color(for kind: FolderMerge.ItemKind) -> Color {
        switch kind {
        case .onlySource: return .green
        case .onlyDest: return .secondary
        case .identical: return .secondary
        case .different: return .orange
        }
    }
}

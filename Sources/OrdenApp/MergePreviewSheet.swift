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
                title: "Fusionar carpetas",
                subtitle: "«\(URL(fileURLWithPath: preview.sourcePath).lastPathComponent)» → «\(URL(fileURLWithPath: preview.destPath).lastPathComponent)»"
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    labeled("Nuevos", preview.onlySourceCount, .green)
                    labeled("Iguales", preview.identicalCount, .secondary)
                    labeled("Distintos", preview.conflictCount, .orange)
                }

                OrdenDialogHintBox(rows: [
                    .init(
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        text: "Los nuevos siempre se copian. Los iguales no se tocan."
                    ),
                    .init(
                        icon: "doc.on.doc",
                        tint: OrdenTheme.accent,
                        text: "Conservar ambos: los que chocan se guardan como «nombre 2»."
                    ),
                    .init(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: "Reemplazar: el archivo que traes pisa al del destino (mismo nombre)."
                    ),
                    .init(
                        icon: asMove ? "trash" : "info.circle.fill",
                        tint: asMove ? .orange : .secondary,
                        text: asMove
                            ? "Si eliges mover, la carpeta de origen va a la Papelera al confirmar."
                            : "⌘Z deshace bien la opción «conservar ambos»; con reemplazo el archivo viejo no se recupera fácil."
                    )
                ])

                if preview.items.isEmpty {
                    Text("No hay diferencias que mostrar.")
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
                }
            }
            .padding(20)
        } footer: {
            HStack(spacing: 10) {
                Button("Cancelar") { browser.cancelPendingMerge() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Conservar ambos") {
                    browser.confirmPendingMerge(overwriteConflicts: false)
                }
                .help("Conflictos → nombre 2")
                Button(asMove ? "Reemplazar y mover" : "Reemplazar conflictos") {
                    browser.confirmPendingMerge(overwriteConflicts: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("El que traes pisa al del destino")
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
        case .onlySource: return "nuevo"
        case .onlyDest: return "solo destino"
        case .identical: return "igual"
        case .different: return "conflicto"
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

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
                        text: "Se copian los archivos nuevos. Los que chocan se guardan con otro nombre. El destino no se borra."
                    ),
                    .init(
                        icon: asMove ? "trash" : "info.circle.fill",
                        tint: asMove ? .orange : OrdenTheme.accent,
                        text: asMove
                            ? "Al confirmar, la carpeta de origen va a la Papelera (es un movimiento + fusión)."
                            : "Es una fusión por copia. ⌘Z puede deshacer los archivos nuevos."
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
                    .frame(minHeight: 200)
                }
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: asMove ? "Mover + fusionar" : "Solo copiar",
                cancelTitle: "Cancelar",
                actionTitle: asMove ? "Fusionar y mover" : "Fusionar copia",
                onCancel: { browser.cancelPendingMerge() },
                onAction: { browser.confirmPendingMerge() }
            )
        }
        .frame(width: 560)
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

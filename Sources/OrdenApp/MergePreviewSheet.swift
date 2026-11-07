import SwiftUI
import OrdenCore

struct MergePreviewSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    let preview: FolderMerge.Preview

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
                    .init(icon: "checkmark.circle.fill", tint: .green, text: "Copia lo que falta y renombra conflictos. No borra el destino."),
                    .init(icon: "info.circle.fill", tint: OrdenTheme.accent, text: "Revisa la lista antes de confirmar. ⌘Z deshace la copia.")
                ])

                List(preview.items.prefix(80)) { item in
                    HStack {
                        Text(item.relativePath)
                            .font(.caption.monospaced())
                        Spacer()
                        Text(label(for: item.kind))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color(for: item.kind))
                    }
                }
                .frame(minHeight: 200)
            }
            .padding(20)
        } footer: {
            OrdenDialogFooter(
                shortcutHint: nil,
                cancelTitle: "Cancelar",
                actionTitle: "Fusionar copia",
                onCancel: { browser.pendingMergePreview = nil },
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

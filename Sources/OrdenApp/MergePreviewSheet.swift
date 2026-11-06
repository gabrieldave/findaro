import SwiftUI
import OrdenCore

struct MergePreviewSheet: View {
    @EnvironmentObject private var browser: BrowserModel
    let preview: FolderMerge.Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fusionar carpetas")
                .font(.title2.weight(.bold))
            Text("«\(URL(fileURLWithPath: preview.sourcePath).lastPathComponent)» → «\(URL(fileURLWithPath: preview.destPath).lastPathComponent)»")
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                labeled("Nuevos", preview.onlySourceCount, .green)
                labeled("Iguales", preview.identicalCount, .secondary)
                labeled("Distintos", preview.conflictCount, .orange)
            }

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
            .frame(minHeight: 220)

            HStack {
                Button("Cancelar", role: .cancel) {
                    browser.pendingMergePreview = nil
                }
                Spacer()
                Button("Fusionar copia (solo faltantes + renombrar conflictos)") {
                    browser.confirmPendingMerge()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }

    private func labeled(_ title: String, _ n: Int, _ color: Color) -> some View {
        VStack {
            Text("\(n)").font(.title3.weight(.bold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
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

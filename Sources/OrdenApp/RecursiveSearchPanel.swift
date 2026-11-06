import SwiftUI
import OrdenCore

struct RecursiveSearchPanel: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Búsqueda en subcarpetas", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if browser.deepSearchRunning {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancelar") { browser.cancelDeepSearch() }
                        .controlSize(.small)
                } else {
                    Button("Cerrar") { browser.clearDeepSearch() }
                        .controlSize(.small)
                }
            }

            if let p = browser.deepSearchProgress {
                Text(
                    p.done
                        ? "Listo · \(p.matched) resultados · \(p.visitedFolders) carpetas"
                        : "Revisando \(p.visitedFolders) carpetas · \(p.matched) hallazgos…"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if !p.currentFolder.isEmpty {
                    Text(p.currentFolder)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if browser.deepSearchHits.isEmpty, browser.deepSearchProgress?.done == true {
                Text("Sin coincidencias")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(browser.deepSearchHits.prefix(60)) { hit in
                Button {
                    if hit.isDirectory {
                        browser.navigate(to: hit.path)
                    } else {
                        browser.navigate(to: (hit.path as NSString).deletingLastPathComponent)
                        browser.selectOnly(hit.path)
                    }
                } label: {
                    HStack {
                        Image(systemName: hit.isDirectory ? "folder.fill" : "doc")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.name).lineLimit(1)
                            Text(hit.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

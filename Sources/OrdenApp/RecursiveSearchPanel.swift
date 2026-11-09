import SwiftUI
import OrdenCore

struct RecursiveSearchPanel: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Label(
                    browser.deepSearchQuery.isEmpty
                        ? L10n.s("Búsqueda en subcarpetas", "Subfolder Search")
                        : (L10n.isEnglish ? "«\(browser.deepSearchQuery)» in subfolders" : "«\(browser.deepSearchQuery)» en subcarpetas"),
                    systemImage: "magnifyingglass"
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                Spacer(minLength: 8)
                if browser.deepSearchRunning {
                    ProgressView()
                        .controlSize(.small)
                    Button(L10n.s("Detener", "Stop")) { browser.cancelDeepSearch() }
                        .controlSize(.small)
                }
                Button {
                    browser.clearDeepSearch()
                } label: {
                    Label(L10n.s("Salir de búsqueda", "Exit Search"), systemImage: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.regular)
                .help(L10n.s("Vuelve al orden normal de la carpeta · Esc", "Return to normal folder order · Esc"))
            }

            Text(L10n.s("Por nombre (parcial). `*.png` = .png. Clic en un resultado → va a la fila. Esc o «Salir» para volver al orden normal.", "By partial name. `*.png` = .png. Click a result to jump to row. Esc or «Exit» to return to normal view."))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let p = browser.deepSearchProgress {
                Text(
                    p.done
                        ? L10n.s("Listo · \(p.matched) resultados · \(p.visitedFolders) carpetas", "Done · \(p.matched) results · \(p.visitedFolders) folders")
                        : L10n.s("Revisando \(p.visitedFolders) carpetas · \(p.matched) hallazgos…", "Scanning \(p.visitedFolders) folders · \(p.matched) matches…")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if !browser.deepSearchRoot.isEmpty {
                    Text("\(L10n.s("Ámbito", "Scope")): \(shortPath(browser.deepSearchRoot)) ↓")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !p.currentFolder.isEmpty, !p.done {
                    Text(shortPath(p.currentFolder))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if browser.deepSearchHits.isEmpty, browser.deepSearchProgress?.done == true {
                Text(L10n.s("Sin coincidencias de nombre bajo esta carpeta", "No matching names found in this folder hierarchy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !browser.deepSearchHits.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(browser.deepSearchHits.prefix(80)) { hit in
                            Button {
                                browser.openDeepSearchHit(hit)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: hit.isDirectory ? "folder.fill" : "doc")
                                        .foregroundStyle(hit.isDirectory ? OrdenTheme.accent : .secondary)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hit.name)
                                            .lineLimit(1)
                                        Text(relativePath(hit.path))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 0)
                                    if !hit.isDirectory, hit.size > 0 {
                                        Text(ByteCountFormatter.string(fromByteCount: hit.size, countStyle: .file))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func relativePath(_ path: String) -> String {
        let root = browser.deepSearchRoot
        guard !root.isEmpty else { return shortPath(path) }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        if path == root { return "." }
        return shortPath(path)
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

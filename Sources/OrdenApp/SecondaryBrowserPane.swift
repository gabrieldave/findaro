import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

/// Panel derecho del modo dual: carpeta destino para mover/copiar desde la izquierda.
struct SecondaryBrowserPane: View {
    @EnvironmentObject private var browser: BrowserModel

    private var focused: Bool { browser.focusedPane == .secondary }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            if let err = browser.secondaryError {
                ContentUnavailableView("No se pudo abrir", systemImage: "exclamationmark.folder", description: Text(err))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { browser.focusPane(.secondary) }
            } else if browser.secondaryEntries.isEmpty {
                ContentUnavailableView(
                    "Vacío",
                    systemImage: "folder",
                    description: Text("Suelta archivos aquí o usa «Mover →» · clic activa el panel")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { browser.focusPane(.secondary) }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .findaroPanelChrome(focused: focused, cornerRadius: OrdenTheme.radiusWindow)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            browser.focusPane(.secondary)
        })
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1.fill")
                    .foregroundStyle(OrdenTheme.accent)
                Text("Destino")
                    .font(.subheadline.weight(.semibold))
                if focused {
                    FindaroStatusPill(title: "activo", kind: .processing)
                }
                Spacer(minLength: 0)
                if !focused {
                    Button {
                        browser.focusDestinationPane()
                    } label: {
                        Label("Activar", systemImage: "arrow.right.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OrdenTheme.accent)
                    .controlSize(.small)
                    .help("Enfoca Destino · Tab · ⌘⇧→ · o clic en vacío")
                }
                Button {
                    browser.goUpSecondary()
                } label: {
                    Image(systemName: "arrow.up.left")
                }
                .buttonStyle(.borderless)
                .help("Subir en el panel derecho")
                Button {
                    browser.transferPrimarySelectionToSecondary(copy: false)
                } label: {
                    Label("Mover →", systemImage: "arrow.right.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                .disabled(browser.selectedIDs.isEmpty)
                .help("Mueve la selección de Origen (izquierda) aquí · ⌘⇧M")
                Button {
                    browser.transferPrimarySelectionToSecondary(copy: true)
                } label: {
                    Text("Copiar →")
                        .font(.caption.weight(.semibold))
                }
                .controlSize(.small)
                .disabled(browser.selectedIDs.isEmpty)
                .help("Copia la selección de Origen aquí")
                Button {
                    browser.transferSecondarySelectionToPrimary(copy: false)
                } label: {
                    Label("← Origen", systemImage: "arrow.left.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
                .disabled(browser.secondarySelectedIDs.isEmpty)
                .help("Mueve lo seleccionado aquí hacia Origen (izquierda). También puedes arrastrar.")
            }

            Text(shortPath(browser.secondaryPath))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(browser.secondaryPath)

            Text("Clic en vacío activa · Arrastra · Tab cambia panel")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture { browser.focusPane(.secondary) }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(browser.secondaryEntries.enumerated()), id: \.element.id) { index, entry in
                    secondaryRow(entry, zebra: index.isMultiple(of: 2))
                }
                // Zona vacía amplia: clic enfoca Destino al instante.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 480)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        browser.focusPane(.secondary)
                        browser.secondarySelectedIDs = []
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func secondaryRow(_ entry: FileEntry, zebra: Bool) -> some View {
        let selected = browser.secondarySelectedIDs.contains(entry.id)
        let cut = browser.isCutPending(path: entry.path)
        return HStack(spacing: 8) {
            Image(systemName: entry.category.symbolName)
                .foregroundStyle(Color(hex: entry.category.tintHex))
                .frame(width: 18)
            Text(entry.name)
                .lineLimit(1)
                .strikethrough(cut)
            Spacer(minLength: 0)
            if !entry.isDirectory {
                Text(FolderSizer.format(entry.size))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected
                ? OrdenTheme.accent.opacity(0.28)
                : (zebra ? Color.white.opacity(0.03) : Color.clear)
        )
        .opacity(cut ? 0.42 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            browser.focusPane(.secondary)
            browser.openSecondaryEntry(entry)
        }
        .onTapGesture(count: 1) {
            browser.selectSecondaryOnly(entry.id)
        }
        .onDrag {
            if !browser.secondarySelectedIDs.contains(entry.id) {
                browser.selectSecondaryOnly(entry.id)
            }
            return NSItemProvider(contentsOf: URL(fileURLWithPath: entry.path)) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Mover a Origen") {
                browser.selectSecondaryOnly(entry.id)
                browser.transferSecondarySelectionToPrimary(copy: false)
            }
            Button("Copiar a Origen") {
                browser.selectSecondaryOnly(entry.id)
                browser.transferSecondarySelectionToPrimary(copy: true)
            }
            Divider()
            if entry.isDirectory {
                Button("Abrir aquí") { browser.openSecondaryEntry(entry) }
            } else {
                Button("Abrir") { browser.openSecondaryEntry(entry) }
            }
            Button("Usar como destino") {
                if entry.isDirectory {
                    browser.navigateSecondary(to: entry.path)
                }
            }
            .disabled(!entry.isDirectory)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        DualPaneDrop.handle(providers) { paths, copy in
            browser.focusPane(.secondary)
            if paths.isEmpty {
                browser.transferPrimarySelectionToSecondary(copy: copy)
            } else {
                _ = browser.dropPathsOnSecondary(paths, copy: copy)
            }
        }
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

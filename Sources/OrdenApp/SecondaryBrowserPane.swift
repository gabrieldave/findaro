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
            } else if browser.secondaryEntries.isEmpty {
                ContentUnavailableView(
                    "Vacío",
                    systemImage: "folder",
                    description: Text("Suelta archivos aquí o usa «Mover →»")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focused ? OrdenTheme.accent : Color.white.opacity(0.06), lineWidth: focused ? 2 : 1)
        )
        .onTapGesture { browser.focusPane(.secondary) }
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
                    Text("activo")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OrdenTheme.accent.opacity(0.25), in: Capsule())
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
                    .help("Enfoca Destino · Tab · ⌘⇧→")
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

            Text("Arrastra entre paneles · ← Origen / Mover → · Tab cambia panel")
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
            }
        }
    }

    private func secondaryRow(_ entry: FileEntry, zebra: Bool) -> some View {
        let selected = browser.secondarySelectedIDs.contains(entry.id)
        return HStack(spacing: 8) {
            Image(systemName: entry.category.symbolName)
                .foregroundStyle(Color(hex: entry.category.tintHex))
                .frame(width: 18)
            Text(entry.name)
                .lineLimit(1)
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
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
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

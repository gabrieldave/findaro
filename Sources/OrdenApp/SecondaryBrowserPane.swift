import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

/// Panel derecho del modo dual: mismas capacidades que Origen (lista, naranja, menú…).
struct SecondaryBrowserPane: View {
    @EnvironmentObject private var browser: BrowserModel

    private var focused: Bool { browser.focusedPane == .secondary }

    var body: some View {
        VStack(spacing: 0) {
            header
            FileBrowserPane(pane: .secondary)
                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                    DualPaneDrop.handle(providers) { paths, copy in
                        browser.focusPane(.secondary)
                        if paths.isEmpty {
                            browser.transferPrimarySelectionToSecondary(copy: copy)
                        } else {
                            _ = browser.dropPathsOnSecondary(paths, copy: copy)
                        }
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .findaroPanelChrome(focused: focused, cornerRadius: OrdenTheme.radiusWindow)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            browser.focusPane(.secondary)
        })
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
                    browser.swapPaneFolders()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Intercambiar carpetas Origen ↔ Destino")
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
                .help("Mueve lo seleccionado en Origen → aquí · ⌘⇧M")
                Button {
                    browser.transferPrimarySelectionToSecondary(copy: true)
                } label: {
                    Text("Copiar →")
                        .font(.caption.weight(.semibold))
                }
                .controlSize(.small)
                .help("Copia lo seleccionado en Origen → aquí")
                Button {
                    browser.transferSecondarySelectionToPrimary(copy: false)
                } label: {
                    Label("← Mover", systemImage: "arrow.left.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.small)
                .help("Mueve lo seleccionado aquí → Origen")
                Button {
                    browser.transferSecondarySelectionToPrimary(copy: true)
                } label: {
                    Text("← Copiar")
                        .font(.caption.weight(.semibold))
                }
                .controlSize(.small)
                .help("Copia lo seleccionado aquí → Origen")
            }

            // Tap en ruta/ayuda enfoca Destino; no envolver los botones (SwiftUI se come el clic).
            VStack(alignment: .leading, spacing: 4) {
                Text(shortPath(browser.secondaryPath))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(browser.secondaryPath)
                Text("Misma lista que Origen · ⌘+clic naranja · Arrastra ↔ · Tab cambia panel")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { browser.focusPane(.secondary) }
        }
        .padding(10)
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

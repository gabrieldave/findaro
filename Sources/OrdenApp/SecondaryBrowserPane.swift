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
                            _ = browser.dropPathsOnPane(paths, pane: .secondary, optionHeld: copy)
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
                Text(L10n.s("Destino", "Destination"))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                if focused {
                    FindaroStatusPill(title: L10n.s("activo", "active"), kind: .processing)
                }
                Spacer(minLength: 0)
                // En paneles < ~520 pt: iconos; nunca cortar el título Destino.
                ViewThatFits(in: .horizontal) {
                    destinationHeaderActions(compact: false)
                    destinationHeaderActions(compact: true)
                }
            }

            // Tap en ruta/ayuda enfoca Destino; no envolver los botones (SwiftUI se come el clic).
            VStack(alignment: .leading, spacing: 4) {
                PathBreadcrumbBar(pane: .secondary)
                Text(L10n.s("Misma lista que Origen · ⌘+clic naranja · Arrastra ↔ · Tab cambia panel", "Same features as Origin · ⌘+click orange · Drag ↔ · Tab swaps pane"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { browser.focusPane(.secondary) }
        }
        .padding(10)
    }

    @ViewBuilder
    private func destinationHeaderActions(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 8) {
            if !focused {
                Button {
                    browser.focusDestinationPane()
                } label: {
                    if compact {
                        Image(systemName: "arrow.right.circle.fill")
                    } else {
                        Label(L10n.s("Activar", "Activate"), systemImage: "arrow.right.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.small)
                .help(L10n.s("Enfoca Destino · Tab · ⌘⇧→ · o clic en vacío", "Focus Destination · Tab · ⌘⇧→ · or click in empty space"))
            }
            Button {
                browser.swapPaneFolders()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .help(L10n.s("Intercambiar carpetas Origen ↔ Destino", "Swap folders Origin ↔ Destination"))
            Button {
                browser.goUpSecondary()
            } label: {
                Image(systemName: "arrow.up.left")
            }
            .buttonStyle(.borderless)
            .help(L10n.s("Subir en el panel derecho", "Go up in right pane"))
            Button {
                browser.transferSecondarySelectionToPrimary(copy: false)
            } label: {
                if compact {
                    Image(systemName: "arrow.left.circle.fill")
                } else {
                    Label(L10n.s("← Mover", "← Move"), systemImage: "arrow.left.circle.fill")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.small)
            .help(L10n.s("Mueve lo seleccionado aquí → Origen", "Move selection here → Origin"))
            Button {
                browser.transferSecondarySelectionToPrimary(copy: true)
            } label: {
                if compact {
                    Image(systemName: "doc.on.doc")
                } else {
                    Text(L10n.s("← Copiar", "← Copy"))
                        .font(.caption.weight(.semibold))
                }
            }
            .controlSize(.small)
            .help(L10n.s("Copia lo seleccionado aquí → Origen", "Copy selection here → Origin"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

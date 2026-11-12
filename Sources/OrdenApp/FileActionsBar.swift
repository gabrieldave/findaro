import SwiftUI
import OrdenCore

/// Densidad de la barra de acciones según ancho útil del detalle.
enum ActionBarDensity: Equatable {
    case roomy
    case compact
    case micro

    static func resolve(detailWidth: CGFloat, metrics: OrdenDisplayMetrics) -> ActionBarDensity {
        // Umbrales más altos: en ventanas típicas de laptop no ocultar etiquetas.
        if detailWidth < 480 || (metrics.isCompact && detailWidth < 620) {
            return .micro
        }
        if detailWidth < 780 || metrics.isCompact {
            return .compact
        }
        return .roomy
    }

    var controlSize: ControlSize {
        switch self {
        case .roomy: return .regular
        case .compact, .micro: return .small
        }
    }

    func label(_ full: String, short: String) -> String? {
        switch self {
        case .roomy: return full
        case .compact: return short
        case .micro: return nil
        }
    }
}

/// Barra de acciones: grupos juntos, separados con «|», se parten en filas si no caben.
struct FileActionsBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.ordenMetrics) private var metrics
    @Environment(\.ordenWindowWidth) private var detailWidth

    private var density: ActionBarDensity {
        ActionBarDensity.resolve(detailWidth: detailWidth, metrics: metrics)
    }

    /// Espacio dentro de un grupo (casi pegados).
    private let inGroup: CGFloat = 3
    /// Espacio alrededor del |
    private let aroundPipe: CGFloat = 6

    var body: some View {
        ActionBarFlow(spacing: aroundPipe, lineSpacing: 6) {
            group {
                chip(L10n.s("Nueva carpeta", "New Folder"), L10n.s("Carpeta", "Folder"), "folder.badge.plus", prominent: true, help: L10n.s("Nueva carpeta · ⇧⌘N", "New Folder · ⇧⌘N"), enabled: true) {
                    browser.promptNewFolder()
                }
                chip(L10n.s("Nuevo archivo", "New File"), L10n.s("Archivo", "File"), "doc.badge.plus", help: L10n.s("Nuevo archivo · ⌘N", "New File · ⌘N"), enabled: true) {
                    browser.promptNewFile()
                }
            }

            pipe

            group {
                chip(
                    browser.showAssistantPanel ? L10n.s("Cerrar IA", "Close AI") : L10n.s("Asistente", "Assistant"),
                    browser.showAssistantPanel ? L10n.s("Cerrar IA", "Close AI") : L10n.s("IA", "AI"),
                    "sparkles",
                    smart: true,
                    help: L10n.s("Asistente · ⌘5", "AI Assistant · ⌘5"),
                    enabled: true
                ) { browser.showAssistantPanel.toggle() }
                chip(
                    browser.dualPaneEnabled ? L10n.s("Un panel", "Single pane") : L10n.s("Dos paneles", "Dual pane"),
                    browser.dualPaneEnabled ? L10n.s("1 panel", "1 pane") : L10n.s("2 paneles", "2 panes"),
                    "rectangle.split.2x1",
                    prominent: browser.dualPaneEnabled,
                    help: browser.dualPaneEnabled ? L10n.s("Volver a un solo panel", "Return to single pane") : L10n.s("Dos paneles Origen | Destino", "Dual panes Origin | Destination"),
                    enabled: true
                ) { browser.toggleDualPane() }
                if browser.dualPaneEnabled {
                    chip(L10n.s("Mover →", "Move →"), "→ Dest", "arrow.right.circle.fill", prominent: true, help: L10n.s("Selección Origen → Destino · ⌘⇧M", "Selection Origin → Destination · ⌘⇧M"), enabled: true) {
                        browser.transferPrimarySelectionToSecondary(copy: false)
                    }
                    chip(L10n.s("← Origen", "← Origin"), "← Orig", "arrow.left.circle.fill", smart: true, help: L10n.s("Selección Destino → Origen", "Selection Destination → Origin"), enabled: true) {
                        browser.transferSecondarySelectionToPrimary(copy: false)
                    }
                    chip("Swap", "Swap", "arrow.left.arrow.right", help: L10n.s("Intercambiar carpetas Origen ↔ Destino", "Swap folders Origin ↔ Destination"), enabled: true) {
                        browser.swapPaneFolders()
                    }
                }
            }

            pipe

            group {
                chip(
                    browser.activeSelectedEntries.count > 1 ? L10n.s("Renombrado masivo", "Batch Rename") : L10n.s("Renombrar", "Rename"),
                    browser.activeSelectedEntries.count > 1 ? L10n.s("Lote", "Batch") : L10n.s("Nombre", "Name"),
                    browser.activeSelectedEntries.count > 1 ? "pencil.and.list.clipboard" : "pencil",
                    help: L10n.s("Renombrar o renombrado masivo (panel activo)", "Rename or batch rename (active pane)"),
                    enabled: browser.activeHasSelection
                ) {
                    browser.promptRename()
                }
                chip(L10n.s("Duplicar", "Duplicate"), L10n.s("Dup", "Dup"), "plus.square.on.square", help: L10n.s("Duplicar · ⌘D", "Duplicate · ⌘D"), enabled: browser.activeHasSelection) {
                    browser.duplicateSelection()
                }
                chip(L10n.s("Copiar", "Copy"), L10n.s("Copiar", "Copy"), "doc.on.doc", help: L10n.s("Copiar a bandeja · ⌘C", "Copy to tray · ⌘C"), enabled: browser.activeHasSelection) {
                    browser.addSelectionToShelf(intent: .copy)
                }
                chip(L10n.s("Cortar", "Cut"), L10n.s("Cortar", "Cut"), "scissors", help: L10n.s("Cortar a bandeja · ⌘X", "Cut to tray · ⌘X"), enabled: browser.activeHasSelection) {
                    browser.addSelectionToShelf(intent: .move)
                }
                chip(L10n.s("Pegar", "Paste"), L10n.s("Pegar", "Paste"), "doc.on.clipboard", help: L10n.s("Pegar en panel activo · ⌘V", "Paste in active pane · ⌘V"), enabled: !browser.shelf.isEmpty || browser.canPasteFiles) {
                    browser.depositShelfHere()
                }
            }

            pipe

            group {
                chip(
                    browser.shelf.isEmpty ? L10n.s("Bandeja", "Tray") : "\(L10n.s("Bandeja", "Tray")) (\(browser.shelf.count))",
                    browser.shelf.isEmpty ? L10n.s("Bandeja", "Tray") : "Tray (\(browser.shelf.count))",
                    "tray.and.arrow.down.fill",
                    help: L10n.s("Meter en bandeja", "Put in tray"),
                    enabled: browser.activeHasSelection
                ) { browser.addSelectionToShelf(intent: .move) }
                chip("Dropover", "Drop", "circle.dashed", help: L10n.s("Abrir en Dropover", "Open in Dropover"), enabled: !browser.outboundPaths.isEmpty) {
                    browser.sendOutboundToDropover()
                }
                chip(L10n.s("Rutas", "Paths"), L10n.s("Rutas", "Paths"), "terminal", help: L10n.s("Copiar rutas", "Copy paths"), enabled: !browser.outboundPaths.isEmpty) {
                    browser.copyOutboundPaths()
                }
            }

            pipe

            group {
                chip(L10n.s("Terminal", "Terminal"), L10n.s("Term", "Term"), "terminal", help: L10n.s("Abrir Terminal en esta carpeta · ⌘⌥T", "Open Terminal in this folder · ⌘⌥T"), enabled: true) {
                    browser.openTerminalHere()
                }
                chip(L10n.s("A Favoritos", "To Favorites"), L10n.s("Favorito", "Favorite"), "star.fill", help: L10n.s("A Favoritos", "Add to Favorites"), enabled: true) {
                    browser.addFoldersToFavoritesFromUI()
                }
                if browser.isViewingTrash {
                    chip(L10n.s("Restaurar", "Restore"), L10n.s("Sacar", "Extract"), "arrow.uturn.backward", prominent: true, help: L10n.s("Sacar de la Papelera", "Restore from Trash"), enabled: browser.activeHasSelection) {
                        browser.restoreSelectionFromTrash()
                    }
                } else {
                    chip(L10n.s("Papelera", "Trash"), L10n.s("Basura", "Trash"), "trash", role: .destructive, help: L10n.s("Papelera · ⌫ · ⌘Z restaura", "Move to Trash · ⌫ · ⌘Z restores"), enabled: browser.activeHasSelection) {
                        browser.moveSelectionToTrash()
                    }
                }
            }
        }
        .padding(.horizontal, metrics.isCompact ? 6 : 8)
        .padding(.vertical, metrics.isCompact ? 4 : 5)
        .background(OrdenTheme.panelFill.opacity(0.96), in: RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous).strokeBorder(OrdenTheme.hairline, lineWidth: 1))
    }

    private var pipe: some View {
        Text("|")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: inGroup, content: content)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func chip(
        _ full: String,
        _ short: String,
        _ systemImage: String,
        prominent: Bool = false,
        smart: Bool = false,
        role: ButtonRole? = nil,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let title = density.label(full, short: short)
        Group {
            if role == .destructive {
                Button(role: .destructive, action: action) { chipLabel(title: title, systemImage: systemImage) }
                    .buttonStyle(FindaroToolbarButtonStyle(destructive: true))
            } else if smart {
                Button(action: action) { chipLabel(title: title, systemImage: systemImage) }
                    .buttonStyle(FindaroToolbarButtonStyle(smart: true))
            } else if prominent {
                Button(action: action) { chipLabel(title: title, systemImage: systemImage) }
                    .buttonStyle(FindaroToolbarButtonStyle(prominent: true))
            } else {
                Button(action: action) { chipLabel(title: title, systemImage: systemImage) }
                    .buttonStyle(FindaroToolbarButtonStyle())
            }
        }
        .controlSize(density.controlSize)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(full)
    }

    @ViewBuilder
    private func chipLabel(title: String?, systemImage: String) -> some View {
        if let title {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } else {
            Image(systemName: systemImage)
                .frame(minWidth: 16, minHeight: 16)
        }
    }
}

// MARK: - Flow (envuelve grupos en varias filas)

/// Coloca subvistas en filas; si no caben, baja a la siguiente.
private struct ActionBarFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let arranged = arrange(proposal: proposal, subviews: subviews)
        return arranged.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in arranged.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(arranged.sizes[index])
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint], sizes: [CGSize]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }

        let height = y + rowHeight
        let width = maxWidth.isFinite ? maxWidth : totalWidth
        return (CGSize(width: width, height: height), origins, sizes)
    }
}

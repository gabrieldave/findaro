import SwiftUI

/// Densidad de la barra de acciones según ancho útil del detalle.
enum ActionBarDensity: Equatable {
    case roomy
    case compact
    case micro

    static func resolve(detailWidth: CGFloat, metrics: OrdenDisplayMetrics) -> ActionBarDensity {
        if detailWidth < 560 || (metrics.isCompact && detailWidth < 720) {
            return .micro
        }
        if detailWidth < 860 || metrics.isCompact {
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
                chip("Nueva carpeta", "Carpeta", "folder.badge.plus", prominent: true, help: "Nueva carpeta · ⇧⌘N", enabled: true) {
                    browser.promptNewFolder()
                }
                chip("Nuevo archivo", "Archivo", "doc.badge.plus", help: "Nuevo archivo · ⌘N", enabled: true) {
                    browser.promptNewFile()
                }
            }

            pipe

            group {
                chip(
                    browser.showAssistantPanel ? "Cerrar IA" : "Asistente",
                    browser.showAssistantPanel ? "Cerrar IA" : "IA",
                    "sparkles",
                    smart: true,
                    help: "Asistente · ⌘5",
                    enabled: true
                ) { browser.showAssistantPanel.toggle() }
                chip(
                    browser.dualPaneEnabled ? "Un panel" : "Dos paneles",
                    browser.dualPaneEnabled ? "1 panel" : "2 paneles",
                    "rectangle.split.2x1",
                    prominent: browser.dualPaneEnabled,
                    help: browser.dualPaneEnabled ? "Volver a un solo panel" : "Dos paneles Origen | Destino",
                    enabled: true
                ) { browser.toggleDualPane() }
                if browser.dualPaneEnabled {
                    chip("Mover →", "→ Dest", "arrow.right.circle.fill", prominent: true, help: "Selección Origen → Destino · ⌘⇧M", enabled: true) {
                        browser.transferPrimarySelectionToSecondary(copy: false)
                    }
                    chip("← Origen", "← Orig", "arrow.left.circle.fill", smart: true, help: "Selección Destino → Origen", enabled: true) {
                        browser.transferSecondarySelectionToPrimary(copy: false)
                    }
                    chip("Swap", "Swap", "arrow.left.arrow.right", help: "Intercambiar carpetas Origen ↔ Destino", enabled: true) {
                        browser.swapPaneFolders()
                    }
                }
            }

            pipe

            group {
                chip("Renombrar", "Nombre", "pencil", help: "Renombrar (panel activo)", enabled: browser.activeSelectedEntries.count == 1) {
                    browser.promptRename()
                }
                chip("Duplicar", "Dup", "plus.square.on.square", help: "Duplicar · ⌘D", enabled: browser.activeHasSelection) {
                    browser.duplicateSelection()
                }
                chip("Copiar", "Copiar", "doc.on.doc", help: "Copiar a bandeja · ⌘C", enabled: browser.activeHasSelection) {
                    browser.addSelectionToShelf(intent: .copy)
                }
                chip("Cortar", "Cortar", "scissors", help: "Cortar a bandeja · ⌘X", enabled: browser.activeHasSelection) {
                    browser.addSelectionToShelf(intent: .move)
                }
                chip("Pegar", "Pegar", "doc.on.clipboard", help: "Pegar en panel activo · ⌘V", enabled: !browser.shelf.isEmpty || browser.canPasteFiles) {
                    browser.depositShelfHere()
                }
            }

            pipe

            group {
                chip(
                    browser.shelf.isEmpty ? "Bandeja" : "Bandeja (\(browser.shelf.count))",
                    browser.shelf.isEmpty ? "Bandeja" : "Ban (\(browser.shelf.count))",
                    "tray.and.arrow.down.fill",
                    help: "Meter en bandeja",
                    enabled: browser.activeHasSelection
                ) { browser.addSelectionToShelf(intent: .move) }
                chip("Dropover", "Drop", "circle.dashed", help: "Abrir en Dropover", enabled: !browser.outboundPaths.isEmpty) {
                    browser.sendOutboundToDropover()
                }
                chip("Rutas", "Rutas", "terminal", help: "Copiar rutas", enabled: !browser.outboundPaths.isEmpty) {
                    browser.copyOutboundPaths()
                }
            }

            pipe

            group {
                chip("Terminal", "Term", "terminal", help: "Abrir Terminal en esta carpeta · ⌘⌥T", enabled: true) {
                    browser.openTerminalHere()
                }
                chip("A Favoritos", "Favorito", "star.fill", help: "A Favoritos", enabled: true) {
                    browser.addFoldersToFavoritesFromUI()
                }
                if browser.isViewingTrash {
                    chip("Restaurar", "Sacar", "arrow.uturn.backward", prominent: true, help: "Sacar de la Papelera", enabled: browser.activeHasSelection) {
                        browser.restoreSelectionFromTrash()
                    }
                } else {
                    chip("Papelera", "Basura", "trash", role: .destructive, help: "Papelera · ⌘⌫", enabled: browser.activeHasSelection) {
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

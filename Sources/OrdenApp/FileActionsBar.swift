import SwiftUI

/// Densidad de la barra de acciones según ancho útil del detalle.
enum ActionBarDensity: Equatable {
    /// Ventana amplia: texto completo.
    case roomy
    /// Media: nombres cortos + botones small.
    case compact
    /// Estrecha: solo iconos (tooltip con el nombre) + varias filas.
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

    var chipMinWidth: CGFloat {
        switch self {
        case .roomy: return 108
        case .compact: return 76
        case .micro: return 34
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

/// Barra de acciones adaptable: se encoje y reparte en filas en pantallas chicas.
struct FileActionsBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.ordenMetrics) private var metrics
    @Environment(\.ordenWindowWidth) private var detailWidth

    private var density: ActionBarDensity {
        ActionBarDensity.resolve(detailWidth: detailWidth, metrics: metrics)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: density.chipMinWidth, maximum: density == .micro ? 44 : 160), spacing: 6)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            chip(
                full: "Nueva carpeta",
                short: "Carpeta",
                systemImage: "folder.badge.plus",
                prominent: true,
                tint: OrdenTheme.accent,
                help: "Nueva carpeta · ⇧⌘N",
                enabled: true
            ) { browser.promptNewFolder() }

            chip(
                full: "Nuevo archivo",
                short: "Archivo",
                systemImage: "doc.badge.plus",
                prominent: true,
                tint: OrdenTheme.accent,
                help: "Nuevo archivo · ⌘N",
                enabled: true
            ) { browser.promptNewFile() }

            chip(
                full: browser.showAssistantPanel ? "Cerrar IA" : "Asistente",
                short: browser.showAssistantPanel ? "Cerrar IA" : "IA",
                systemImage: "sparkles",
                prominent: true,
                tint: browser.showAssistantPanel ? .orange : OrdenTheme.accent,
                help: "Asistente · ⌘5",
                enabled: true
            ) { browser.showAssistantPanel.toggle() }

            chip(
                full: browser.dualPaneEnabled ? "Un panel" : "Dos paneles",
                short: browser.dualPaneEnabled ? "1 panel" : "2 paneles",
                systemImage: "rectangle.split.2x1",
                prominent: true,
                tint: browser.dualPaneEnabled ? .orange : OrdenTheme.accent,
                help: browser.dualPaneEnabled
                    ? "Volver a un solo panel"
                    : "Dos paneles: Origen | Destino · arrastra o Mover → / ← Origen",
                enabled: true
            ) { browser.toggleDualPane() }

            if browser.dualPaneEnabled {
                chip(
                    full: "Mover →",
                    short: "→ Dest",
                    systemImage: "arrow.right.circle.fill",
                    prominent: true,
                    tint: .orange,
                    help: "Mover selección a Destino · ⌘⇧M",
                    enabled: !browser.selectedIDs.isEmpty
                ) { browser.transferPrimarySelectionToSecondary(copy: false) }

                chip(
                    full: "← Origen",
                    short: "← Orig",
                    systemImage: "arrow.left.circle.fill",
                    prominent: true,
                    tint: .purple,
                    help: "Mover selección de Destino a Origen",
                    enabled: !browser.secondarySelectedIDs.isEmpty
                ) { browser.transferSecondarySelectionToPrimary(copy: false) }
            }

            chip(
                full: "Renombrar",
                short: "Nombre",
                systemImage: "pencil",
                help: "Renombrar · Return",
                enabled: browser.selectedIDs.count == 1
            ) { browser.promptRename() }

            chip(
                full: "Duplicar",
                short: "Dup",
                systemImage: "plus.square.on.square",
                help: "Duplicar · ⌘D",
                enabled: !browser.selectedIDs.isEmpty
            ) { browser.duplicateSelection() }

            chip(
                full: "Copiar",
                short: "Copiar",
                systemImage: "doc.on.doc",
                help: "A la bandeja (copiar) · ⌘C",
                enabled: !browser.selectedIDs.isEmpty
            ) { browser.addSelectionToShelf(intent: .copy) }

            chip(
                full: "Cortar",
                short: "Cortar",
                systemImage: "scissors",
                help: "A la bandeja (mover) · ⌘X",
                enabled: !browser.selectedIDs.isEmpty
            ) { browser.addSelectionToShelf(intent: .move) }

            chip(
                full: "Pegar",
                short: "Pegar",
                systemImage: "doc.on.clipboard",
                help: "Soltar bandeja aquí · ⌘V",
                enabled: !browser.shelf.isEmpty || browser.canPasteFiles
            ) { browser.depositShelfHere() }

            chip(
                full: browser.shelf.isEmpty ? "Bandeja" : "Bandeja (\(browser.shelf.count))",
                short: browser.shelf.isEmpty ? "Bandeja" : "Ban (\(browser.shelf.count))",
                systemImage: "tray.and.arrow.down.fill",
                prominent: true,
                tint: OrdenTheme.accent,
                help: "Meter selección en la bandeja",
                enabled: !browser.selectedIDs.isEmpty
            ) { browser.addSelectionToShelf(intent: .move) }

            chip(
                full: "Dropover",
                short: "Drop",
                systemImage: "circle.dashed",
                help: "Abrir en Dropover",
                enabled: !browser.outboundPaths.isEmpty
            ) { browser.sendOutboundToDropover() }

            chip(
                full: "Rutas",
                short: "Rutas",
                systemImage: "terminal",
                help: "Copiar rutas al portapapeles",
                enabled: !browser.outboundPaths.isEmpty
            ) { browser.copyOutboundPaths() }

            chip(
                full: "A Favoritos",
                short: "Favorito",
                systemImage: "star.fill",
                help: "Añadir carpeta a Favoritos",
                enabled: true
            ) { browser.addFoldersToFavoritesFromUI() }

            chip(
                full: "Papelera",
                short: "Basura",
                systemImage: "trash",
                prominent: false,
                tint: .red,
                role: .destructive,
                help: "Mover a la Papelera · ⌘⌫",
                enabled: !browser.selectedIDs.isEmpty
            ) { browser.moveSelectionToTrash() }
        }
        .padding(.horizontal, metrics.isCompact ? 6 : 8)
        .padding(.vertical, metrics.isCompact ? 4 : 5)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .help(density == .micro
            ? "Pantalla estrecha: toca un icono — el nombre sale al pasar el mouse"
            : "Acciones de archivos")
    }

    @ViewBuilder
    private func chip(
        full: String,
        short: String,
        systemImage: String,
        prominent: Bool = false,
        tint: Color? = nil,
        role: ButtonRole? = nil,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let title = density.label(full, short: short)
        Group {
            if prominent {
                Button(role: role, action: action) { chipLabel(title: title, systemImage: systemImage) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            } else if role == .destructive {
                Button(role: .destructive, action: action) { chipLabel(title: title, systemImage: systemImage) }
                    .buttonStyle(.bordered)
            } else {
                Button(action: action) { chipLabel(title: title, systemImage: systemImage) }
                    .buttonStyle(.bordered)
                    .tint(tint)
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
                .minimumScaleFactor(0.8)
        } else {
            Image(systemName: systemImage)
                .frame(minWidth: 18, minHeight: 18)
        }
    }
}

import SwiftUI
import OrdenCore

/// Una sola barra contextual (~38 pt): crear + filtros/acciones + resumen.
/// Sustituye SortBar + FileActionsBar + ruta duplicada de FolderStatsBar.
struct ContextualChromeBar: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.ordenMetrics) private var metrics
    @Environment(\.ordenWindowWidth) private var windowWidth

    private var detailWidth: CGFloat {
        max(320, metrics.detailWidth > 1 ? metrics.detailWidth : (windowWidth - metrics.sidebarWidth))
    }

    /// En 2 paneles el chrome es compartido: preferir iconos para no truncar.
    private var iconOnly: Bool {
        detailWidth < 720 || (browser.dualPaneEnabled && detailWidth < 1200)
    }
    private var showShortLabels: Bool {
        detailWidth >= 1100 && !browser.dualPaneEnabled
    }
    private var controlSize: ControlSize { detailWidth < 1100 || browser.dualPaneEnabled ? .small : .regular }

    var body: some View {
        HStack(spacing: 8) {
            leadingCreate

            Divider().frame(height: 18)

            ViewThatFits(in: .horizontal) {
                if !iconOnly { centerRoomy }
                centerCompact
                centerIconsOnly
            }

            Spacer(minLength: 8)

            trailingStats
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous)
                .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
        )
        .controlSize(controlSize)
    }

    // MARK: - Leading

    private var leadingCreate: some View {
        HStack(spacing: 4) {
            Button {
                browser.promptNewFolder()
            } label: {
                if iconOnly {
                    Image(systemName: "folder.badge.plus")
                } else {
                    Label(L10n.s("+ Nueva", "+ New"), systemImage: "folder.badge.plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OrdenTheme.accent)
            .help(L10n.s("Nueva carpeta · ⇧⌘N", "New Folder · ⇧⌘N"))

            Button {
                browser.promptNewFile()
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .help(L10n.s("Nuevo archivo · ⌘N", "New File · ⌘N"))

            if browser.dualPaneEnabled {
                Button {
                    browser.toggleDualPane()
                } label: {
                    dualPaneLabel
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .help(L10n.s("Alternar dos paneles · ⇧⌘D", "Toggle Dual Pane · ⇧⌘D"))
            } else {
                Button {
                    browser.toggleDualPane()
                } label: {
                    dualPaneLabel
                }
                .buttonStyle(.bordered)
                .help(L10n.s("Alternar dos paneles · ⇧⌘D", "Toggle Dual Pane · ⇧⌘D"))
            }
        }
    }

    @ViewBuilder
    private var dualPaneLabel: some View {
        if detailWidth < 640 {
            Image(systemName: "rectangle.split.2x1")
        } else {
            Label(L10n.s("2 paneles", "2 panes"), systemImage: "rectangle.split.2x1")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Center variants

    @ViewBuilder
    private var centerRoomy: some View {
        if browser.activeHasSelection {
            selectionActions(showLabels: showShortLabels, showRenameLabel: detailWidth >= 560)
        } else {
            idleFilters(showLabels: true)
        }
    }

    @ViewBuilder
    private var centerCompact: some View {
        if browser.activeHasSelection {
            selectionActions(showLabels: false, showRenameLabel: detailWidth >= 560)
        } else {
            idleFilters(showLabels: false)
        }
    }

    @ViewBuilder
    private var centerIconsOnly: some View {
        if browser.activeHasSelection {
            selectionActions(showLabels: false, showRenameLabel: false)
        } else {
            idleFilters(showLabels: false)
        }
    }

    private func idleFilters(showLabels: Bool) -> some View {
        HStack(spacing: 4) {
            Menu {
                Button("\(L10n.s("Todos", "All")) · \(browser.entries.count)") {
                    browser.clearCategoryFilter()
                }
                if !browser.categoryCounts.isEmpty {
                    Divider()
                    ForEach(browser.categoryCounts, id: \.category) { row in
                        Button("\(row.category.labelLocalized) · \(row.count)") {
                            browser.categoryFilter = row.category
                        }
                    }
                }
            } label: {
                chipLabel(showLabels ? L10n.s("Tipo", "Type") : nil, "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderedButton)
            .tint(browser.categoryFilter == nil ? nil : OrdenTheme.accent)
            .help(L10n.s("Filtrar por tipo", "Filter by type"))

            Button {
                browser.toggleDownloadsTodayMode()
            } label: {
                chipLabel(
                    showLabels ? (browser.downloadsTodayMode ? L10n.s("Hoy ✓", "Today ✓") : L10n.s("Hoy", "Today")) : nil,
                    browser.downloadsTodayMode ? "xmark.circle" : "arrow.down.circle"
                )
            }
            .buttonStyle(.bordered)
            .tint(browser.downloadsTodayMode ? .orange : nil)
            .help(L10n.s("Solo descargados / agregados hoy", "Only downloaded / added today"))

            if !browser.downloadsTodayMode {
                Button {
                    if browser.cleanupMode {
                        browser.exitCleanupMode()
                    } else {
                        browser.showHeaviestForCleanup()
                    }
                } label: {
                    chipLabel(
                        showLabels ? (browser.cleanupMode ? L10n.s("Pesados ✓", "Largest ✓") : L10n.s("Pesados", "Largest")) : nil,
                        "internaldrive"
                    )
                }
                .buttonStyle(.bordered)
                .tint(browser.cleanupMode ? .orange : nil)
                .help(L10n.s("Más pesados primero (no borra nada)", "Largest first (does not delete)"))
            }

            Button {
                if browser.showDeepSearchPanel {
                    browser.clearDeepSearch()
                } else {
                    browser.promptDeepSearch()
                }
            } label: {
                chipLabel(
                    showLabels
                        ? (browser.showDeepSearchPanel ? L10n.s("Salir", "Exit") : L10n.s("Subcarpetas", "Subfolders"))
                        : nil,
                    browser.showDeepSearchPanel ? "xmark.circle.fill" : "folder.badge.magnifyingglass"
                )
            }
            .buttonStyle(.bordered)
            .tint(browser.showDeepSearchPanel ? .orange : nil)
            .disabled(browser.deepSearchRunning)
            .help(L10n.s("Buscar en subcarpetas · ⌘4", "Search in subfolders · ⌘4"))

            if !browser.downloadsTodayMode {
                Menu {
                    Section(L10n.s("Cambiar orden (se guarda)", "Change Order (Saved)")) {
                        sortButtons(scope: .everywhere)
                    }
                    Divider()
                    Section(L10n.s("Solo esta carpeta", "This Folder Only")) {
                        sortButtons(scope: .thisFolder)
                    }
                    if browser.hasFolderOverride {
                        Button(L10n.s("Quitar orden propio (usar global)", "Remove folder override (use global)")) {
                            browser.useGlobalDefaultHere()
                        }
                    }
                    Divider()
                    Button(L10n.s("Fijar como orden global", "Set as global order")) {
                        browser.useDownloadsStyleEverywhere()
                    }
                    Divider()
                    Menu(L10n.s("Plantillas de vista", "View presets")) {
                        if browser.viewTemplates.isEmpty {
                            Text(L10n.s("Sin plantillas todavía", "No presets yet"))
                        } else {
                            ForEach(browser.viewTemplates) { template in
                                Button(template.displayName) {
                                    browser.applyViewTemplate(template)
                                }
                            }
                        }
                        Divider()
                        Button(L10n.s("Guardar vista actual…", "Save current view…")) {
                            browser.promptSaveViewTemplate()
                        }
                    }
                } label: {
                    chipLabel(showLabels ? L10n.s("Ordenar", "Sort") : nil, "arrow.up.arrow.down")
                }
                .menuStyle(.borderedButton)
                .help(L10n.s("Ordenar y plantillas de vista", "Sort and view presets"))
            }

            if !browser.shelf.isEmpty || browser.canPasteFiles {
                Button {
                    browser.depositShelfHere()
                } label: {
                    chipLabel(showLabels ? L10n.s("Pegar", "Paste") : nil, "doc.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .help(L10n.s("Pegar · ⌘V", "Paste · ⌘V"))
            }

            Button {
                browser.cleanMacOSJunkInActiveFolder()
            } label: {
                chipLabel(
                    (browser.isExternalOrNetworkActiveVolume && showLabels) ? L10n.s("Limpiar", "Clean") : nil,
                    "sparkles.rectangle.stack"
                )
            }
            .buttonStyle(.bordered)
            .tint(browser.isExternalOrNetworkActiveVolume ? .orange : nil)
            .help(L10n.s("Limpiar basura .DS_Store y ._ en esta carpeta", "Clean .DS_Store & ._ junk in this folder"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func selectionActions(showLabels: Bool, showRenameLabel: Bool) -> some View {
        let count = browser.activeSelectedEntries.count
        let showMoveLabel = detailWidth >= 720
        return HStack(spacing: 4) {
            Text("\(count) \(L10n.s("sel.", "sel."))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OrdenTheme.textSecondary)
                .padding(.horizontal, 6)

            if count > 1 {
                Button {
                    browser.promptBatchRename()
                } label: {
                    chipLabel(
                        showRenameLabel ? L10n.s("Renombrar (\(count))", "Rename (\(count))") : nil,
                        "pencil.line"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .help(L10n.s("Renombrado masivo Pro · ⌃⇧R", "Batch Rename Pro · ⌃⇧R"))
            } else {
                Button {
                    browser.promptRename()
                } label: {
                    chipLabel(
                        showRenameLabel ? L10n.s("Renombrar", "Rename") : nil,
                        "character.cursor.ibeam"
                    )
                }
                .buttonStyle(.bordered)
                .help(L10n.s("Renombrar · ⌃R / F2", "Rename · ⌃R / F2"))
            }

            if browser.dualPaneEnabled {
                if browser.activeIsSecondary {
                    Button {
                        browser.transferSecondarySelectionToPrimary(copy: false)
                    } label: {
                        chipLabel(showMoveLabel ? L10n.s("← Mover", "← Move") : nil, "arrow.left.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .help(L10n.s("Mover selección Destino → Origen · ⌘⌥⇧M", "Move selection Destination → Origin · ⌘⌥⇧M"))
                } else {
                    Button {
                        browser.transferPrimarySelectionToSecondary(copy: false)
                    } label: {
                        chipLabel(showMoveLabel ? L10n.s("Mover →", "Move →") : nil, "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .help(L10n.s("Mover selección Origen → Destino · ⌘⇧M", "Move selection Origin → Destination · ⌘⇧M"))
                }
            }

            iconAction(L10n.s("Abrir", "Open"), "arrow.up.forward.app", showLabels) {
                browser.openSelection()
            }
            iconAction(L10n.s("Vista rápida", "Quick Look"), "eye", showLabels) {
                browser.openPreviewExplicitly()
            }
            iconAction(L10n.s("Copiar", "Copy"), "doc.on.doc", showLabels) {
                browser.addSelectionToShelf(intent: .copy)
            }
            .help(L10n.s("Copiar a bandeja · ⌘C", "Copy to tray · ⌘C"))
            iconAction(L10n.s("Cortar", "Cut"), "scissors", showLabels) {
                browser.addSelectionToShelf(intent: .move)
            }
            .help(L10n.s("Cortar a bandeja · ⌘X", "Cut to tray · ⌘X"))

            if !browser.shelf.isEmpty || browser.canPasteFiles {
                iconAction(L10n.s("Pegar", "Paste"), "doc.on.clipboard", showLabels) {
                    browser.depositShelfHere()
                }
                .help(L10n.s("Pegar aquí · ⌘V", "Paste here · ⌘V"))
            }

            Menu {
                Button(L10n.s("Duplicar", "Duplicate")) {
                    browser.duplicateSelection()
                }
                Button(L10n.s("Comprimir en ZIP", "Compress as ZIP")) {
                    browser.compressSelection()
                }
                Button(L10n.s("Añadir a Favoritos", "Add to Favorites")) {
                    browser.addFoldersToFavoritesFromUI()
                }
                Button(L10n.s("Enviar a Dropover", "Send to Dropover")) {
                    browser.sendOutboundToDropover()
                }
                .disabled(browser.outboundPaths.isEmpty)
                Button(L10n.s("Copiar ruta", "Copy Path")) {
                    browser.copyOutboundPaths()
                }
                .disabled(browser.outboundPaths.isEmpty)
                Divider()
                Button(L10n.s("Modo Renombrado Pro…", "Batch Rename Pro…")) {
                    browser.promptBatchRename()
                }
                Button(L10n.s("Limpiar .DS_Store y ._ aquí", "Clean .DS_Store & ._ Here")) {
                    browser.cleanMacOSJunkInActiveFolder()
                }
            } label: {
                chipLabel(showLabels ? L10n.s("Más", "More") : nil, "ellipsis.circle")
            }
            .menuStyle(.borderedButton)
            .help(L10n.s("Más acciones de selección", "More selection actions"))

            if browser.isViewingTrash {
                Button {
                    browser.restoreSelectionFromTrash()
                } label: {
                    chipLabel(showLabels ? L10n.s("Restaurar", "Restore") : nil, "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
            } else {
                Button(role: .destructive) {
                    browser.moveSelectionToTrash()
                } label: {
                    chipLabel(showLabels ? L10n.s("Papelera", "Trash") : nil, "trash")
                }
                .buttonStyle(.bordered)
                .tint(OrdenTheme.danger)
                .help(L10n.s("Papelera · ⌫", "Trash · ⌫"))
            }

            Button {
                browser.cancelSelection()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(L10n.s("Limpiar selección · Esc", "Clear selection · Esc"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var trailingStats: some View {
        HStack(spacing: 6) {
            if browser.isMeasuringSizes {
                ProgressView().controlSize(.mini)
            }
            Text(statsLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(OrdenTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var statsLabel: String {
        let size = browser.folderTotalLabel
        let count: String
        if browser.downloadsTodayMode {
            count = "\(browser.visibleEntries.count) " + L10n.s("hoy", "today") + " / \(browser.entries.count)"
        } else {
            count = "\(browser.visibleEntries.count) " + L10n.s("ítems", "items")
        }
        return "\(size) · \(count)"
    }

    // MARK: - Helpers

    @ViewBuilder
    private func chipLabel(_ title: String?, _ systemImage: String) -> some View {
        if let title {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Image(systemName: systemImage)
        }
    }

    private func iconAction(
        _ title: String,
        _ systemImage: String,
        _ showLabels: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            chipLabel(showLabels ? title : nil, systemImage)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func sortButtons(scope: SortSaveScope) -> some View {
        Button(L10n.s("Estilo Descargas (tipos · Agregado ↓)", "Downloads Style (Types · Added ↓)")) {
            browser.applyRule(.downloads, scope: scope)
        }
        Button(L10n.s("Solo Agregado · lo más nuevo arriba", "Date Added Only · Newest on top")) {
            browser.applyRule(.newestAddedFirst, scope: scope)
        }
        Button(L10n.s("Nombre A→Z", "Name A→Z")) {
            browser.applyRule(
                SortRule(keys: [.name(ascending: true)], foldersFirst: true),
                scope: scope
            )
        }
        Button(L10n.s("Por tipo fijo", "By Fixed Type")) {
            browser.applyRule(.byType, scope: scope)
        }
        Button(L10n.s("Más pesados primero", "Largest First")) {
            browser.applyRule(.heaviestFirst, scope: scope)
        }
        Toggle(
            L10n.s("Carpetas arriba", "Folders on top"),
            isOn: Binding(
                get: { browser.rule.foldersFirst },
                set: { on in
                    var r = browser.rule
                    r.foldersFirst = on
                    browser.applyRule(r, scope: scope)
                }
            )
        )
    }
}

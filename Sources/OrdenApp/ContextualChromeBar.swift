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
        }
    }

    // MARK: - Center variants

    @ViewBuilder
    private var centerRoomy: some View {
        if browser.activeHasSelection {
            selectionActions(showLabels: showShortLabels)
        } else {
            idleFilters(showLabels: true)
        }
    }

    @ViewBuilder
    private var centerCompact: some View {
        if browser.activeHasSelection {
            selectionActions(showLabels: false)
        } else {
            idleFilters(showLabels: false)
        }
    }

    @ViewBuilder
    private var centerIconsOnly: some View {
        if browser.activeHasSelection {
            selectionActions(showLabels: false)
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
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func selectionActions(showLabels: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(browser.activeSelectedEntries.count) \(L10n.s("sel.", "sel."))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OrdenTheme.textSecondary)
                .padding(.horizontal, 6)

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
            iconAction(L10n.s("Pegar", "Paste"), "doc.on.clipboard", showLabels, enabled: !browser.shelf.isEmpty || browser.canPasteFiles) {
                browser.depositShelfHere()
            }
            iconAction(
                browser.activeSelectedEntries.count > 1 ? L10n.s("Lote", "Batch") : L10n.s("Renombrar", "Rename"),
                browser.activeSelectedEntries.count > 1 ? "pencil.and.list.clipboard" : "pencil",
                showLabels
            ) {
                browser.promptRename()
            }
            iconAction(L10n.s("Duplicar", "Duplicate"), "plus.square.on.square", showLabels) {
                browser.duplicateSelection()
            }
            iconAction(L10n.s("Favorito", "Favorite"), "star", showLabels) {
                browser.addFoldersToFavoritesFromUI()
            }
            iconAction("Dropover", "circle.dashed", showLabels, enabled: !browser.outboundPaths.isEmpty) {
                browser.sendOutboundToDropover()
            }
            iconAction(L10n.s("Ruta", "Path"), "link", showLabels, enabled: !browser.outboundPaths.isEmpty) {
                browser.copyOutboundPaths()
            }

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

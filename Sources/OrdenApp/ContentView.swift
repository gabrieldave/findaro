import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

struct ContentView: View {
    @AppStorage("findaro_app_language") private var appLangStorage: String = "auto"
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var session: BrowserWindowSession

    /// Se actualiza en cada resize — fuerza redibujar sidebar + iconos al momento.
    @State private var layoutGeneration: Int = 0
    @State private var windowWidth: CGFloat = 0
    @State private var windowHeight: CGFloat = 0
    @State private var metrics: OrdenDisplayMetrics = .resolve(windowSize: .zero)
    @State private var lastDisplayRecoverAt: Date = .distantPast

    /// REGLA: el menú izquierdo NUNCA se colapsa; el ancho sí se adapta a la pantalla.
    private var sidebarWidth: CGFloat { metrics.sidebarWidth }
    private var detailMinWidth: CGFloat { metrics.detailMinWidth }
    private var assistantWidth: CGFloat { metrics.assistantWidth }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: sidebarWidth)
                    .frame(minWidth: sidebarWidth, idealWidth: sidebarWidth, maxWidth: sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .layoutPriority(1)
                    .background(OrdenTheme.sidebarFill)
                    .accessibilityLabel(L10n.s("Menú lateral", "Sidebar"))
                    // Al terminar un resize (layoutGeneration++) reaparece si SwiftUI lo había “congelado”
                    .id("sidebar-\(layoutGeneration)-\(Int(sidebarWidth))")

                Divider().opacity(0.45)

                detailColumn
                    // minWidth 0: comprime el detalle, NUNCA el sidebar
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0)
                    .environment(
                        \.ordenWindowWidth,
                        max(0, windowWidth - sidebarWidth - (browser.showAssistantPanel ? assistantWidth : 0))
                    )
                    .environment(\.ordenLayoutGeneration, layoutGeneration)

                if browser.showAssistantPanel {
                    Divider().opacity(0.35)
                    AssistantPanel()
                        .frame(width: assistantWidth)
                        .frame(minWidth: assistantWidth, maxWidth: assistantWidth)
                        .layoutPriority(1)
                }
            }

            // Preview imagen/vídeo: NSPanel hijo (MediaPreviewController), no overlay
            // SwiftUI aquí — se desmontaba al cambiar layout/carpeta/monitor.
        }
        .frame(
            minWidth: sidebarWidth + detailMinWidth + (browser.showAssistantPanel ? assistantWidth : 0),
            minHeight: metrics.windowMinHeight
        )
        .ordenAdaptiveTypography(metrics)
        .background(OrdenTheme.windowFill)
        // Dependencia explícita: cualquier lectura invalida layout al cambiar el ancho
        .animation(nil, value: layoutGeneration)
        .animation(nil, value: windowWidth)
        .animation(nil, value: metrics)
        .background(
            WindowLayoutProbe(
                onChange: { size in applyWindowSize(size) },
                onLiveResizeEnd: { size in
                    applyWindowSize(size)
                    // Al soltar el resize: mismo “refresco” que cambiar el modo de vista
                    layoutGeneration &+= 1
                    OrdenWindowFit.applyToOpenWindows()
                },
                onScreenChange: {
                    recoverAfterDisplayChange()
                },
                onHostWindow: { window in
                    browser.hostWindow = window
                }
            )
        )
        .readLayoutWidth { w in
            applyWindowSize(CGSize(width: w, height: windowHeight))
        }
        .onAppear {
            OrdenWindowFit.applyToOpenWindows()
            metrics = .resolve(windowSize: CGSize(width: windowWidth, height: windowHeight))
            LicenseStore.shared.evaluateLocalState()
            if !LicenseStore.shared.state.isUsable {
                browser.showLicenseSheet = true
            }
        }
        .searchable(
            text: $browser.searchText,
            placement: .toolbar,
            prompt: L10n.s("Buscar en Findaro…", "Search in Findaro…")
        )
        .onSubmit(of: .search) {
            browser.startDeepSearch()
        }
        .onAppear {
            // Solo actualizar refs; el monitor NSEvent es único a nivel app (AppDelegate).
            SelectionCancelMonitor.install(browser: browser, session: session)
        }
        .modifier(BrowserToolbarModifier())
        .modifier(BrowserDialogsModifier(shortPath: shortPath))
        // Espacio → Vista rápida lo maneja SelectionCancelMonitor (más fiable que
        // onKeyPress: el SearchField del toolbar a menudo se come el evento SwiftUI).
        .onKeyPress(keys: [.downArrow], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            guard !browser.hasModalSheet else { return .ignored }
            browser.openSelection()
            return .handled
        }
        .onKeyPress(keys: [.delete], phases: .down) { press in
            // ⌫ solo (estilo Windows). En campos de texto no interceptar.
            guard press.modifiers.isEmpty else { return .ignored }
            guard !browser.hasModalSheet else { return .ignored }
            if FindaroTextInput.isEditing || browser.isAssistantFocused || browser.pathOmniboxEditing {
                return .ignored
            }
            browser.moveSelectionToTrash()
            return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard !press.modifiers.contains(.command) else { return .ignored }
            // Omnibox / sheets / texto / asistente: no abrir ni renombrar detrás.
            if browser.pathOmniboxEditing {
                browser.submitPathOmnibox()
                return .handled
            }
            if browser.hasModalSheet { return .ignored }
            if FindaroTextInput.isEditing || browser.isAssistantFocused { return .ignored }
            if browser.explorerKeyboardProfile {
                browser.openSelection()
            } else {
                guard browser.selectedIDs.count == 1 else { return .ignored }
                browser.promptRename()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if browser.pathOmniboxEditing {
                browser.cancelPathOmnibox()
                return .handled
            }
            if browser.hasModalSheet {
                browser.dismissModalSheet()
                return .handled
            }
            browser.cancelSelectionOrClearTray()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow], phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            browser.goBack()
            return .handled
        }
        .onKeyPress(keys: [.rightArrow], phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            browser.goForward()
            return .handled
        }
        // Espacio / Esc / ⌥← / ⌥→ también en SelectionCancelMonitor (NSEvent)
    }

    private func applyWindowSize(_ size: CGSize) {
        let w = size.width
        let h = size.height > 1 ? size.height : windowHeight
        guard w > 1 else { return }
        let cell = metrics.iconCell + metrics.iconSpacing
        let prevCols = max(1, Int((max(0, windowWidth - sidebarWidth) + metrics.iconSpacing) / max(1, cell)))
        let nextCols = max(1, Int((max(0, w - sidebarWidth) + metrics.iconSpacing) / max(1, cell)))
        let widthChanged = abs(w - windowWidth) >= 0.5
        let heightChanged = abs(h - windowHeight) >= 0.5
        if widthChanged { windowWidth = w }
        if heightChanged { windowHeight = h }

        let nextMetrics = OrdenDisplayMetrics.resolve(
            windowSize: CGSize(width: w, height: h > 1 ? h : 640)
        )
        let metricsChanged = nextMetrics != metrics
        if metricsChanged {
            metrics = nextMetrics
        }
        // Sube generación cuando cambia cuántas columnas de iconos caben (o al primer layout)
        if nextCols != prevCols || layoutGeneration == 0 || metricsChanged {
            layoutGeneration &+= 1
        }
    }

    /// Tras arrastrar Findaro entre monitores: destruir preview efímero + remount layout.
    private func recoverAfterDisplayChange() {
        let now = Date()
        guard now.timeIntervalSince(lastDisplayRecoverAt) > 0.35 else { return }
        lastDisplayRecoverAt = now
        MediaPreviewController.shared.dismiss(restoreFocus: false)
        browser.mediaPreviewEntry = nil
        SelectionCancelMonitor.install(browser: browser, session: session)
        layoutGeneration &+= 1
        metrics = .resolve(windowSize: CGSize(width: max(windowWidth, 1), height: max(windowHeight, 1)))
        DispatchQueue.main.async {
            OrdenWindowFit.applyToOpenWindows()
        }
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            ContextualChromeBar()
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if browser.isViewingTrash {
                TrashActionsBar()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            FolderStatsBar()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            FileDragArmChrome.ReadyBanner()
                .fixedSize(horizontal: false, vertical: true)

            if browser.showDeepSearchPanel {
                RecursiveSearchPanel()
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Con solo la carpeta inteligente abierta basta su propio banner (Editar / Ver carpeta completa).
            if browser.hasActiveViewFilters && (browser.activeSmartFolder == nil || browser.hasFiltersBeyondSmartFolder) {
                ActiveFiltersBar()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            if let dest = browser.folderDropTargetPath {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.body.weight(.bold))
                    Text(L10n.s("Suelta para meter en «\(URL(fileURLWithPath: dest).lastPathComponent)»", "Drop to place into «\(URL(fileURLWithPath: dest).lastPathComponent)»"))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(L10n.s("⌥ copia · ⌘Z deshace", "⌥ copies · ⌘Z undos"))
                        .font(.caption)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                // Banner de altura fija (evita saltos de layout que traban el drop).
                .animation(nil, value: dest)
            }

            Group {
                if browser.dualPaneEnabled {
                    // Siempre 50 % / 50 % — sin HSplitView (evita que Destino se coma el ancho).
                    HStack(spacing: 8) {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(L10n.s("Origen", "Origin"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .fixedSize(horizontal: true, vertical: false)
                                    if browser.focusedPane == .primary {
                                        FindaroStatusPill(title: L10n.s("activo", "active"), kind: .processing)
                                    }
                                    Spacer(minLength: 4)
                                    // En paneles < ~520 pt: iconos; nunca cortar el título Origen.
                                    ViewThatFits(in: .horizontal) {
                                        originHeaderActions(compact: false)
                                        originHeaderActions(compact: true)
                                    }
                                }
                                // Tap en ruta/ayuda enfoca Origen; no envolver botones (bloqueaba Mover/Copiar).
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(shortPath(browser.currentPath))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(browser.currentPath)
                                    Text(L10n.s("Misma lista · naranja · Arrastra ↔ · Swap intercambia carpetas", "Same list · orange · Drag ↔ · Swap exchanges folders"))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { browser.focusOriginPane() }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            FileBrowserPane()
                                .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                                    DualPaneDrop.handle(providers) { paths, copy in
                                        browser.focusOriginPane()
                                        if paths.isEmpty {
                                            browser.transferSecondarySelectionToPrimary(copy: copy)
                                        } else {
                                            _ = browser.dropPathsOnPrimary(paths, copy: copy)
                                        }
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded {
                            browser.focusOriginPane()
                        })
                        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: OrdenTheme.radiusWindow, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: OrdenTheme.radiusWindow, style: .continuous)
                                .strokeBorder(
                                    browser.focusedPane == .primary
                                        ? OrdenTheme.accent.opacity(0.85)
                                        : OrdenTheme.hairline,
                                    lineWidth: browser.focusedPane == .primary ? 2 : 1
                                )
                        )

                        SecondaryBrowserPane()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .enableFileDragArmMonitor(browser: browser)
                } else {
                    FileBrowserPane()
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .enableFileDragArmMonitor(browser: browser)
                }
            }

            DropShelfView()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            if let fraction = browser.transferProgressFraction {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .foregroundStyle(OrdenTheme.accent)
                        Text(browser.transferProgressLabel ?? L10n.s("Transfiriendo…", "Transferring…"))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        FindaroStatusPill(title: L10n.s("En curso", "In progress"), kind: .processing)
                        Spacer(minLength: 0)
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(OrdenTheme.textSecondary)
                    }
                    ProgressView(value: fraction)
                        .tint(OrdenTheme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .findaroSurface(cornerRadius: OrdenTheme.radiusPanel)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            if let status = browser.statusMessage {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title3)
                        .foregroundStyle(OrdenTheme.cyan)
                    Text(status)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        browser.statusMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(OrdenTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.s("Cerrar aviso", "Dismiss notice"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    OrdenTheme.elevatedFill,
                    in: RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OrdenTheme.radiusPanel, style: .continuous)
                        .strokeBorder(OrdenTheme.cyan.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrdenTheme.windowFill)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            browser.importDroppedFiles(providers: providers)
        }
    }

    @ViewBuilder
    private func originHeaderActions(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 8) {
            if browser.focusedPane != .primary {
                Button {
                    browser.focusOriginPane()
                } label: {
                    if compact {
                        Image(systemName: "arrow.left.circle.fill")
                    } else {
                        Label(L10n.s("Activar", "Activate"), systemImage: "arrow.left.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.small)
                .help(L10n.s("Enfoca el panel izquierdo · Tab · ⌘⇧← · o clic en vacío", "Focus left pane · Tab · ⌘⇧← · or click in empty space"))
            }
            Button {
                browser.swapPaneFolders()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .help(L10n.s("Intercambiar carpetas Origen ↔ Destino", "Swap folders Origin ↔ Destination"))
            Button {
                browser.goUp()
            } label: {
                Image(systemName: "arrow.up.left")
            }
            .buttonStyle(.borderless)
            .help(L10n.s("Subir en el panel izquierdo", "Go up in left pane"))
            Button {
                browser.transferPrimarySelectionToSecondary(copy: false)
            } label: {
                if compact {
                    Image(systemName: "arrow.right.circle.fill")
                } else {
                    Label(L10n.s("Mover →", "Move →"), systemImage: "arrow.right.circle.fill")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
            .help(L10n.s("Mueve lo seleccionado aquí → Destino · ⌘⇧M", "Move selection here → Destination · ⌘⇧M"))
            Button {
                browser.transferPrimarySelectionToSecondary(copy: true)
            } label: {
                if compact {
                    Image(systemName: "doc.on.doc")
                } else {
                    Text(L10n.s("Copiar →", "Copy →"))
                        .font(.caption.weight(.semibold))
                }
            }
            .controlSize(.small)
            .help(L10n.s("Copia lo seleccionado aquí → Destino", "Copy selection here → Destination"))
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

// MARK: - Sort bar

struct SortBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(OrdenTheme.accent)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(browser.ruleSummary)
                    .font(.system(.subheadline).weight(.semibold))
                    .lineLimit(1)
                Text(browser.scopeBadge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(browser.hasFolderOverride ? OrdenTheme.warning : OrdenTheme.textSecondary)
            }

            Spacer(minLength: 8)

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
                Label(browser.categoryFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderedButton)
            .tint(browser.categoryFilter == nil ? nil : OrdenTheme.accent)
            .help(L10n.s("Filtra por tipo: imágenes, vídeos, zips…", "Filter by type: images, videos, archives…"))

            Button {
                browser.toggleDownloadsTodayMode()
            } label: {
                Label(
                    browser.downloadsTodayMode ? L10n.s("Salir descargados", "Exit Downloads") : L10n.s("Descargados", "Downloads"),
                    systemImage: browser.downloadsTodayMode ? "xmark.circle" : "arrow.down.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(browser.downloadsTodayMode ? .orange : OrdenTheme.accent)
            .controlSize(.regular)
            .help(L10n.s("Solo lo bajado o agregado hoy en esta carpeta (oculta el resto)", "Only files downloaded or added today in this folder (hides the rest)"))

            if browser.cleanupMode {
                Button {
                    browser.exitCleanupMode()
                } label: {
                    Label(L10n.s("Volver al orden normal", "Back to Normal Order"), systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.regular)
                .help(L10n.s("Quita el orden por peso y regresa al orden que tenías", "Removes size sorting and returns to previous order"))
            } else if !browser.downloadsTodayMode {
                Button {
                    browser.showHeaviestForCleanup()
                } label: {
                    Label(L10n.s("Más pesados", "Largest Files"), systemImage: "gauge.with.dots.needle.67percent")
                }
                .help(L10n.s("No borra nada: solo pone arriba lo que más ocupa espacio", "Does not delete anything: simply lists largest space consumers at top"))
                .controlSize(.regular)
            }

            if !browser.downloadsTodayMode {
                Button {
                    browser.useDownloadsStyleEverywhere()
                } label: {
                    Label(L10n.s("Fijar orden global", "Set Global Order"), systemImage: "arrow.up.and.down.square")
                }
                .help(L10n.s("Aplica este criterio de ordenación a todas las carpetas (no altera el alcance de la búsqueda)", "Applies this sort order to all folders (does not alter search scope)"))
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.regular)
            }

            Button {
                if browser.showDeepSearchPanel {
                    browser.clearDeepSearch()
                } else {
                    browser.promptDeepSearch()
                }
            } label: {
                Label(
                    browser.deepSearchRunning
                        ? L10n.s("Buscando…", "Searching…")
                        : (browser.showDeepSearchPanel ? L10n.s("Salir búsqueda", "Exit Search") : L10n.s("Subcarpetas", "Subfolders")),
                    systemImage: browser.showDeepSearchPanel
                        ? "xmark.circle.fill"
                        : "folder.badge.magnifyingglass"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(browser.showDeepSearchPanel ? .orange : OrdenTheme.accent)
            .controlSize(.regular)
            .disabled(browser.deepSearchRunning)
            .help(
                browser.showDeepSearchPanel
                    ? L10n.s("Cerrar búsqueda y volver al orden normal · Esc", "Close search and return to normal order · Esc")
                    : L10n.s("Por nombre, desde esta carpeta hacia abajo · ⌘4", "By name, from this folder downwards · ⌘4")
            )

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
                } label: {
                    Label(L10n.s("Ordenar", "Sort"), systemImage: "line.3.horizontal.decrease")
                }
                .menuStyle(.borderedButton)

                Menu {
                    if browser.viewTemplates.isEmpty {
                        Text(L10n.s("Sin plantillas todavía", "No presets yet"))
                    } else {
                        Section(L10n.s("Aplicar plantilla", "Apply Preset")) {
                            ForEach(browser.viewTemplates) { template in
                                Button {
                                    browser.applyViewTemplate(template)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.displayName)
                                        Text(template.summaryLocalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button(L10n.s("Guardar vista actual como plantilla…", "Save current view as preset…")) {
                        browser.promptSaveViewTemplate()
                    }
                    if !browser.viewTemplates.isEmpty {
                        Menu(L10n.s("Eliminar plantilla", "Delete Preset")) {
                            ForEach(browser.viewTemplates) { template in
                                Button(role: .destructive) {
                                    browser.deleteViewTemplate(template)
                                } label: {
                                    Text(template.displayName)
                                }
                            }
                        }
                    }
                } label: {
                    Label(L10n.s("Plantillas", "Presets"), systemImage: "rectangle.stack")
                }
                .menuStyle(.borderedButton)
                .help(Self.plantillasHelp)

                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(Self.plantillasHelp)
                    .accessibilityLabel(L10n.s("Qué son las plantillas", "What presets are"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static var plantillasHelp: String {
        L10n.s("""
        Plantillas = formas guardadas de ver tus archivos.

        Ejemplo: ordenas por «Más pesados», eliges lista o iconos, y lo guardas como plantilla «Pesados». Después la vuelves a aplicar con un clic, o dejas esa vista puesta.

        También puedes combinar (tipo + orden) y guardar tu propia mezcla. El menú Ordenar cambia el orden al momento; Plantillas guarda y recarga esas combinaciones.
        """, """
        Presets = saved ways to view your files.

        Example: sort by "Largest Files", select list or icons view, and save as preset "Heavy". You can re-apply it with one click anytime, or keep it active.

        You can also combine file type and sort rules into custom presets. The Sort menu changes views immediately; Presets saves and restores those combinations.
        """)
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

// MARK: - Filtros activos → siempre «Orden normal»

struct ActiveFiltersBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.orange)
            Text(filterSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if canSaveAsSmartFolder {
                Button {
                    browser.promptSaveCurrentViewAsSmartFolder()
                } label: {
                    Label(L10n.s("Guardar en Favoritos", "Save to Favorites"), systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help(L10n.s(
                    "Convierte esta búsqueda en una carpeta inteligente de Favoritos: un clic y vuelves a ver solo estos archivos.",
                    "Turn this search into a smart folder in Favorites: one click brings these files back."
                ))
            }
            Button {
                browser.resetToNormalView()
            } label: {
                Label(L10n.s("Quitar filtro", "Clear Filter"), systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.regular)
            .help(L10n.s("Quita búsqueda, tipo, descargados y atajos · Esc. Al filtrar la lista va por Agregado (más nuevo arriba).", "Clears search, type, downloads and shortcuts · Esc. Filtered views sort by Date Added (newest on top)."))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    /// Búsqueda, Tipo, «Descargados» o atajo → se puede guardar como carpeta inteligente.
    private var canSaveAsSmartFolder: Bool {
        guard browser.activeSmartFolder == nil, !browser.showDeepSearchPanel else { return false }
        return !browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (browser.categoryFilter != nil && browser.categoryFilter != .folder)
            || browser.downloadsTodayMode
            || browser.activeAssistantShortcut != nil
    }

    private var filterSummary: String {
        var parts: [String] = []
        if let smart = browser.activeSmartFolder {
            parts.append(L10n.s("carpeta inteligente «\(smart.name)»", "smart folder “\(smart.name)”"))
        }
        if browser.showDeepSearchPanel {
            parts.append(L10n.s("búsqueda subcarpetas", "subfolder search"))
        }
        if !browser.searchText.isEmpty {
            parts.append(L10n.s("filtro «\(browser.searchText)»", "filter «\(browser.searchText)»"))
        }
        if browser.categoryFilter != nil {
            parts.append(L10n.s("tipo", "type"))
        }
        if browser.downloadsTodayMode {
            parts.append(L10n.s("descargados hoy", "downloaded today"))
        }
        if browser.cleanupMode {
            parts.append(L10n.s("más pesados", "largest files"))
        }
        if browser.activeAssistantShortcut != nil {
            parts.append(L10n.s("atajo", "shortcut"))
        }
        if parts.isEmpty { return L10n.s("Filtros activos · más nuevo arriba", "Active filters · newest on top") }
        return L10n.s("Activo: ", "Active: ") + parts.joined(separator: " · ") + L10n.s(" · más nuevo arriba", " · newest on top")
    }
}

// MARK: - Carpeta inteligente abierta

struct SmartFolderBanner: View {
    @EnvironmentObject private var browser: BrowserModel
    let folder: SmartFolder

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: folder.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(hex: folder.tintHex))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(folder.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if browser.smartFolderLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.s("Buscando…", "Searching…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(countLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(OrdenTheme.accent.opacity(0.18), in: Capsule())
                    }
                }
                Text(folder.summaryLocalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder.summaryLocalized)
            }
            Spacer(minLength: 8)
            Button {
                browser.editSmartFolder(folder)
            } label: {
                Label(L10n.s("Editar", "Edit"), systemImage: "slider.horizontal.3")
            }
            .controlSize(.regular)
            .help(L10n.s("Cambiar tipo, extensiones, fecha o carpeta", "Change type, extensions, date or folder"))
            Button {
                browser.exitSmartFolder()
            } label: {
                Label(L10n.s("Ver carpeta completa", "Show whole folder"), systemImage: "folder")
            }
            .controlSize(.regular)
            .help(L10n.s("Sale de la carpeta inteligente y muestra todo · Esc", "Leave the smart folder and show everything · Esc"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(OrdenTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(OrdenTheme.accent.opacity(0.30), lineWidth: 1)
        )
    }

    private var countLabel: String {
        let n = browser.visibleEntries.count
        var label = n == 1 ? L10n.s("1 archivo", "1 file") : L10n.s("\(n) archivos", "\(n) files")
        if browser.smartFolderTruncated {
            label += L10n.s(" (primeros)", " (first ones)")
        }
        return label
    }
}

// MARK: - Stats / cleanup

struct FolderStatsBar: View {
    @EnvironmentObject private var browser: BrowserModel

    /// Solo banners especiales; la ruta vive en la toolbar (PathBreadcrumbBar).
    private var hasBanner: Bool {
        browser.activeSmartFolder != nil
            || browser.activeAssistantShortcut != nil
            || browser.downloadsTodayMode
            || browser.cleanupMode
    }

    var body: some View {
        if hasBanner {
            VStack(alignment: .leading, spacing: 8) {
                if let smart = browser.activeSmartFolder {
                    SmartFolderBanner(folder: smart)
                } else if let shortcut = browser.activeAssistantShortcut {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.orange)
                        Text(L10n.s("Atajo «\(shortcut.displayTitle)»: \(browser.visibleEntries.count) coincidencias. El resto está oculto.", "Shortcut «\(shortcut.displayTitle)»: \(browser.visibleEntries.count) matches. The rest is hidden."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button(L10n.s("Mostrar todo", "Show all")) {
                            browser.clearAssistantShortcutFilter()
                        }
                        .controlSize(.regular)
                    }
                } else if browser.downloadsTodayMode {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.orange)
                        Text(L10n.s("Solo descargas / archivos de hoy en esta carpeta. El resto está oculto.", "Only downloads / today's files in this folder. The rest is hidden."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button(L10n.s("Mostrar todo", "Show all")) {
                            browser.exitDownloadsTodayMode()
                        }
                        .controlSize(.small)
                    }
                }

                if browser.cleanupMode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.s("Ordenado por peso (no se borra nada). Toca uno para seleccionarlo:", "Sorted by size (nothing is deleted). Tap one to select it:"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(browser.heaviestPreview.prefix(4)) { entry in
                                Text("\(entry.name) (\(FolderSizer.format(entry.size)))")
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(OrdenTheme.accent.opacity(0.15), in: Capsule())
                                    .lineLimit(1)
                                    .help(entry.path)
                                    .onTapGesture {
                                        browser.selectOnly(entry.id)
                                        browser.statusMessage = entry.path
                                    }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Sidebar (fijo: Favoritos + Ubicaciones siempre visibles)

private struct SidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let path: String
    let systemImage: String
}

struct SidebarView: View {
    @AppStorage("findaro_app_language") private var appLangStorage: String = "en"
    @EnvironmentObject private var browser: BrowserModel
    /// Se incrementa al montar/desmontar discos para refrescar Ubicaciones.
    @State private var volumesTick: Int = 0
    @State private var favoritesDropTargeted = false
    @State private var locationsCollapsed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                FindaroMark(size: 30, showWordmark: true, wordmarkSize: 14, compact: false)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                favoritesDropZone

                locationsSectionHeader
                    .padding(.top, 12)
                if !locationsCollapsed {
                    ForEach(locationItems) { item in
                        sidebarButton(item, isFavoriteSlot: false)
                    }
                }
            }
            .padding(.bottom, 16)
            // volumesTick fuerza recalcular locationItems al conectar USB/discos
            .id(volumesTick)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrdenTheme.sidebarFill)
        .onAppear {
            locationsCollapsed = browser.store.preferences.locationsCollapsed
        }
        .onReceive(NotificationCenter.default.publisher(for: PreferencesStore.preferencesDidChangeNotification)) { _ in
            locationsCollapsed = browser.store.preferences.locationsCollapsed
        }
        .onReceive(
            NotificationCenter.Publisher(
                center: NSWorkspace.shared.notificationCenter,
                name: NSWorkspace.didMountNotification
            )
        ) { _ in volumesTick &+= 1 }
        .onReceive(
            NotificationCenter.Publisher(
                center: NSWorkspace.shared.notificationCenter,
                name: NSWorkspace.didUnmountNotification
            )
        ) { _ in volumesTick &+= 1 }
        .onReceive(
            NotificationCenter.Publisher(
                center: NSWorkspace.shared.notificationCenter,
                name: NSWorkspace.didRenameVolumeNotification
            )
        ) { _ in volumesTick &+= 1 }
    }

    private var locationsSectionHeader: some View {
        HStack(spacing: 6) {
            Text(L10n.s("Ubicaciones", "Locations").uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(OrdenTheme.textMuted)
            Spacer(minLength: 4)
            Button {
                locationsCollapsed.toggle()
                browser.store.update { $0.locationsCollapsed = locationsCollapsed }
            } label: {
                Image(systemName: locationsCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(OrdenTheme.textMuted)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                locationsCollapsed
                    ? L10n.s("Mostrar Ubicaciones", "Show Locations")
                    : L10n.s("Ocultar Ubicaciones", "Hide Locations")
            )
            .accessibilityLabel(
                locationsCollapsed
                    ? L10n.s("Mostrar Ubicaciones", "Show Locations")
                    : L10n.s("Ocultar Ubicaciones", "Hide Locations")
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var favoriteItems: [SidebarItem] {
        browser.store.preferences.favorites.compactMap { path in
            if FindaroDemoMode.isEnabled && !FindaroDemoMode.isAllowedFavorite(path: path) {
                return nil
            }
            let rawName = URL(fileURLWithPath: path).lastPathComponent
            let localizedTitle: String
            if L10n.isEnglish {
                switch rawName.lowercased() {
                case "descargas", "downloads": localizedTitle = "Downloads"
                case "escritorio", "desktop": localizedTitle = "Desktop"
                case "documentos", "documents": localizedTitle = "Documents"
                case "imágenes", "imagenes", "pictures": localizedTitle = "Pictures"
                case "música", "musica", "music": localizedTitle = "Music"
                case "películas", "peliculas", "movies": localizedTitle = "Movies"
                default: localizedTitle = rawName
                }
            } else {
                switch rawName.lowercased() {
                case "descargas", "downloads": localizedTitle = "Descargas"
                case "escritorio", "desktop": localizedTitle = "Escritorio"
                case "documentos", "documents": localizedTitle = "Documentos"
                case "imágenes", "imagenes", "pictures": localizedTitle = "Imágenes"
                case "música", "musica", "music": localizedTitle = "Música"
                case "películas", "peliculas", "movies": localizedTitle = "Películas"
                default: localizedTitle = rawName
                }
            }
            return SidebarItem(
                id: "fav-\(path)",
                title: localizedTitle,
                path: path,
                systemImage: favoriteIcon(for: path)
            )
        }
    }

    /// Igual que Finder → Ubicaciones (las que existan en este Mac).
    private var locationItems: [SidebarItem] {
        _ = volumesTick
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let iCloud = (home as NSString).appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs"
        )
        var clouds: [SidebarLocations.CloudFolder] = []
        let cloudRoot = (home as NSString).appendingPathComponent("Library/CloudStorage")
        if let names = try? fm.contentsOfDirectory(atPath: cloudRoot) {
            for name in names where !name.hasPrefix(".") {
                let path = (cloudRoot as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                clouds.append(.init(name: name, path: path))
            }
        }

        var volumes: [SidebarLocations.Volume] = []
        if let names = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            for name in names {
                if FindaroDemoMode.isExcludedVolume(name: name) { continue }
                let path = "/Volumes/\(name)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                volumes.append(.init(name: name, path: path, resolvedPath: resolved))
            }
        }

        return SidebarLocations.make(
            homePath: home,
            iCloudPath: fm.fileExists(atPath: iCloud) ? iCloud : nil,
            cloudFolders: clouds,
            volumes: volumes,
            trashPath: TrashOps.userTrashPath,
            demoMode: FindaroDemoMode.isEnabled
        ).map {
            SidebarItem(id: $0.id, title: $0.title, path: $0.path, systemImage: $0.systemImage)
        }
    }

    private var favoritesDropZone: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(L10n.s("FAVORITOS", "FAVORITES"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(OrdenTheme.textMuted)
                Spacer(minLength: 4)
                Button {
                    browser.addCurrentFolderToFavorites()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(OrdenTheme.accent)
                }
                .buttonStyle(.plain)
                .help(L10n.s("Añadir la carpeta actual a Favoritos", "Add current folder to Favorites"))
                Button {
                    browser.pickFolderAsFavorite()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.body)
                        .foregroundStyle(OrdenTheme.accent)
                }
                .buttonStyle(.plain)
                .help(L10n.s("Elegir otra carpeta…", "Choose another folder…"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(favoriteItems) { item in
                sidebarButton(item, isFavoriteSlot: true)
            }

            smartFoldersBlock

            Text(favoritesDropTargeted ? L10n.s("Suelta para fijar", "Drop to pin") : L10n.s("Usa «A Favoritos» o suelta desde Finder", "Use «Add to Favorites» or drop from Finder"))
                .font(.caption2)
                .foregroundStyle(favoritesDropTargeted ? OrdenTheme.accent : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    favoritesDropTargeted ? OrdenTheme.accent : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .padding(.horizontal, 6)
        )
        .background(
            favoritesDropTargeted
                ? OrdenTheme.accent.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $favoritesDropTargeted) { providers in
            browser.importFavoritesFromProviders(providers)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(OrdenTheme.textMuted)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func sidebarButton(_ item: SidebarItem, isFavoriteSlot: Bool) -> some View {
        let active = isActive(item.path)
        return Button {
            browser.navigate(to: item.path)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? OrdenTheme.accentHover : OrdenTheme.accent)
                    .frame(width: 22, alignment: .center)
                Text(item.title)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                active ? OrdenTheme.sidebarActiveFill : Color.clear,
                in: RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
                    .strokeBorder(active ? OrdenTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        // Sidebar de ancho fijo: si no caben letras, tooltip con nombre + ruta.
        .help("\(item.title)\n\(item.path)")
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .contextMenu {
            if isFavoriteSlot {
                Button(L10n.s("Mover arriba en Favoritos", "Move Up in Favorites")) {
                    browser.moveFavorite(path: item.path, direction: -1)
                }
                .disabled(browser.store.preferences.favorites.first == item.path)

                Button(L10n.s("Mover abajo en Favoritos", "Move Down in Favorites")) {
                    browser.moveFavorite(path: item.path, direction: 1)
                }
                .disabled(browser.store.preferences.favorites.last == item.path)

                Divider()

                Button(L10n.s("Quitar de Favoritos", "Remove from Favorites"), role: .destructive) {
                    browser.removeFavorite(item.path)
                }
            } else {
                Button(L10n.s("Añadir a Favoritos", "Add to Favorites")) {
                    browser.addFavorite(item.path)
                }
            }
        }
    }

    // MARK: Carpetas inteligentes (dentro de Favoritos)

    @ViewBuilder
    private var smartFoldersBlock: some View {
        if FindaroDemoMode.isEnabled {
            EmptyView()
        } else {
            smartFoldersBlockContent
        }
    }

    @ViewBuilder
    private var smartFoldersBlockContent: some View {
        if !browser.smartFolders.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(L10n.s("INTELIGENTES", "SMART"))
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
            }
            .foregroundStyle(OrdenTheme.textMuted)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .help(L10n.s(
                "Búsquedas guardadas: un clic muestra solo esos archivos. No mueven ni copian nada.",
                "Saved searches: one click shows only those files. Nothing is moved or copied."
            ))

            ForEach(browser.smartFolders) { folder in
                smartFolderButton(folder)
            }
        }

        Button {
            browser.promptNewSmartFolder()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, alignment: .center)
                Text(L10n.s("Nueva carpeta inteligente…", "New Smart Folder…"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(OrdenTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .help(L10n.s(
            "Crea una carpeta que muestra solo lo que eliges: imágenes, PDF, ZIP, lo descargado hoy, cualquier extensión…",
            "Create a folder that shows only what you choose: images, PDFs, ZIPs, today's downloads, any extension…"
        ))
    }

    private func smartFolderButton(_ folder: SmartFolder) -> some View {
        let active = browser.isSmartFolderActive(folder)
        let tint = Color(hex: folder.tintHex)
        return Button {
            // Abrir (o, si ya está abierta, volver a buscar por si hay archivos nuevos).
            browser.openSmartFolder(folder)
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: folder.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22, alignment: .center)
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(OrdenTheme.textMuted)
                        .offset(x: 3, y: 3)
                }
                Text(folder.name)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if active && browser.smartFolderLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else if active {
                    Text("\(browser.visibleEntries.count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                active ? OrdenTheme.sidebarActiveFill : Color.clear,
                in: RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OrdenTheme.radiusControl, style: .continuous)
                    .strokeBorder(active ? OrdenTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help("\(folder.name)\n\(folder.summaryLocalized)")
        .accessibilityAddTraits(active ? [.isSelected] : [])
        .contextMenu {
            Button(L10n.s("Abrir", "Open")) {
                browser.openSmartFolder(folder)
            }
            Button(L10n.s("Editar…", "Edit…")) {
                browser.editSmartFolder(folder)
            }
            Button(L10n.s("Duplicar…", "Duplicate…")) {
                browser.duplicateSmartFolder(folder)
            }
            Divider()
            Button(L10n.s("Mover arriba", "Move Up")) {
                browser.moveSmartFolder(folder, direction: -1)
            }
            .disabled(browser.smartFolders.first?.id == folder.id)
            Button(L10n.s("Mover abajo", "Move Down")) {
                browser.moveSmartFolder(folder, direction: 1)
            }
            .disabled(browser.smartFolders.last?.id == folder.id)
            Divider()
            Button(L10n.s("Quitar de Favoritos (no borra archivos)", "Remove from Favorites (keeps files)"), role: .destructive) {
                browser.deleteSmartFolder(folder)
            }
        }
    }

    private func isActive(_ path: String) -> Bool {
        // Con una carpeta inteligente abierta, la carpeta normal no aparece marcada.
        if browser.activeSmartFolder != nil { return false }
        let a = (path as NSString).standardizingPath
        let b = (browser.currentPath as NSString).standardizingPath
        return a == b
    }

    private func favoriteIcon(for path: String) -> String {
        switch URL(fileURLWithPath: path).lastPathComponent.lowercased() {
        case "downloads": return "arrow.down.circle.fill"
        case "desktop": return "menubar.dock.rectangle"
        case "documents": return "doc.fill"
        case "projects": return "hammer.fill"
        default: return "folder.fill"
        }
    }
}

// MARK: - File pane (clic + marquee)

private struct ListContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 900
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct FileBrowserPane: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.ordenMetrics) private var metrics
    /// Origen (primary) o Destino (secondary) — misma UI y gestos.
    var pane: BrowserModel.PaneFocus = .primary

    private var isSecondary: Bool { pane == .secondary }

    private var paneEntries: [FileEntry] {
        isSecondary ? browser.secondaryEntries : browser.visibleEntries
    }

    private var paneError: String? {
        isSecondary ? browser.secondaryError : browser.errorMessage
    }

    /// Debe coincidir con la altura fija de cada `FileRowButton`.
    private var rowHeight: CGFloat {
        // Respetar el toggle «Rutas» siempre (antes se ocultaban en compacto y el botón “no servía”).
        let base = PressDragSelectLogic.listRowHeight(showPaths: browser.showRowPaths)
        // En compacto el nombre puede ocupar 2 líneas.
        return metrics.isCompact ? max(base, browser.showRowPaths ? 72 : 52) : base
    }

    /// Lista agrupada por categoría + huecos entre bloques (marquesina).
    private var layoutRows: [ListPaneRow] {
        ListPaneLayout.build(entries: paneEntries)
    }

    @Environment(\.ordenWindowWidth) private var detailEnvWidth

    /// Ancho útil del panel de lista. En dual pane NUNCA confiar en el ideal del LazyVStack
    /// (se hincha con las columnas meta y el budget deja de filtrar).
    private var measuredListWidth: CGFloat {
        let detail = max(320, detailEnvWidth > 1 ? detailEnvWidth : metrics.detailWidth)
        if browser.dualPaneEnabled {
            return max(260, detail / 2 - 12)
        }
        // 1 panel: preferir medida del contenedor si es razonable (≤ detalle).
        if listContentWidth > 1, listContentWidth <= detail + 40 {
            return listContentWidth
        }
        return detail
    }

    /// Columnas que caben sin aplastar Nombre (< 220 pt sagrado). No muta PreferencesStore.
    private var visibleListColumns: [ListColumn] {
        let budget = max(0, measuredListWidth - 220 - 38)
        let compact = metrics.isCompact || browser.dualPaneEnabled || measuredListWidth < 700
        return ListColumn.fit(
            preferred: browser.listColumns,
            budget: budget,
            compact: compact
        )
    }

    private var trailingColumnsWidth: CGFloat {
        ListColumn.totalWidth(visibleListColumns, compact: metrics.isCompact) + 38
    }

    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBase: Set<String> = []
    @State private var marqueeAdditive = false
    @State private var marqueeCommitted = false
    @State private var marqueeStartEntryID: String?
    @State private var folderDragPaths: [String] = []
    @State private var folderDragStarted = false
    /// Ancho del contenido de lista (coordenadas del gesto) para separar columna Nombre vs vacío.
    @State private var listContentWidth: CGFloat = 900

    var body: some View {
        Group {
            if let error = paneError {
                if !isSecondary, browser.isViewingTrash {
                    TrashPermissionUnavailable(errorText: error)
                } else {
                    ContentUnavailableView(
                        L10n.s("No se pudo abrir", "Could Not Open"),
                        systemImage: "exclamationmark.folder",
                        description: Text(error)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else if paneEntries.isEmpty, !isSecondary, browser.smartFolderLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.s("Buscando en subcarpetas…", "Searching subfolders…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if paneEntries.isEmpty && (isSecondary || browser.viewMode != .columns) {
                ContentUnavailableView(
                    L10n.s("Vacío", "Empty"),
                    systemImage: "folder",
                    description: Text(isSecondary
                        ? L10n.s("Suelta archivos aquí o usa «Mover →»", "Drop files here or click «Move →»")
                        : L10n.s("No hay elementos con este filtro.", "No items match this filter."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    browser.cancelSelectionFromBackgroundTap(activating: pane)
                }
            } else if isSecondary {
                // Destino: misma lista que Origen (naranja, casillas, menú…).
                listBrowser
            } else {
                switch browser.viewMode {
                case .list:
                    listBrowser
                case .icons:
                    IconsBrowserView()
                case .columns:
                    ColumnsBrowserView()
                case .gallery:
                    GalleryBrowserView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: browser.selectionCancelToken) { _, _ in
            resetMarquee()
        }
    }

    private var listBrowser: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.35)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(layoutRows.enumerated()), id: \.element.id) { index, row in
                            switch row {
                            case .section(let category, let count):
                                CategorySectionHeader(
                                    category: category,
                                    count: count,
                                    pane: pane
                                )
                                .frame(height: ListPaneLayout.sectionHeight)
                                .id(row.id)
                            case .gap(let category):
                                CategoryGapRow(category: category, pane: pane)
                                    .frame(height: ListPaneLayout.gapHeight)
                                    .id(row.id)
                            case .entry(let entry):
                                FileRowButton(
                                    entry: entry,
                                    zebra: index.isMultiple(of: 2),
                                    pane: pane,
                                    columns: visibleListColumns
                                )
                                .frame(height: rowHeight)
                                .id(entry.id)
                            }
                        }
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 480)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                browser.cancelSelectionFromBackgroundTap(activating: pane)
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .coordinateSpace(name: isSecondary ? "fileListSecondary" : "fileList")
                    .overlay(alignment: .topLeading) {
                        if let rect = marqueeRect {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(OrdenTheme.accent.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(OrdenTheme.accent.opacity(0.85), lineWidth: 1)
                                )
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    // Marquesina en vacío. El drag de archivo lo arma AppKit sobre el nombre.
                    .gesture(marqueeGesture)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Medir el contenedor del ScrollView (ancho del panel), no el ideal del LazyVStack.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ListContentWidthKey.self, value: geo.size.width)
                    }
                )
                .onPreferenceChange(ListContentWidthKey.self) { listContentWidth = max($0, 1) }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { oldY, newY in
                    if abs(oldY - newY) > 0.5 {
                        FileDragArmMonitor.shared.invalidateFrames()
                    }
                }
                .onTapGesture {
                    browser.cancelSelectionFromBackgroundTap(activating: pane)
                }
                .onChange(of: browser.revealToken) { _, _ in
                    guard !isSecondary, let id = browser.revealEntryID else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                .onChange(of: isSecondary ? browser.secondarySelectionFocusID : browser.selectionFocusID) { _, newFocus in
                    guard let newFocus else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(newFocus, anchor: nil)
                    }
                }
                .onChange(of: paneEntries.map(\.id)) { _, _ in
                    FileDragArmMonitor.shared.invalidateFrames()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: OrdenTheme.radiusWindow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OrdenTheme.radiusWindow, style: .continuous)
                .strokeBorder(OrdenTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: OrdenTheme.radiusWindow, style: .continuous))
    }

    private func resetMarquee() {
        marqueeStart = nil
        marqueeCurrent = nil
        marqueeBase = []
        marqueeCommitted = false
        marqueeStartEntryID = nil
        folderDragPaths = []
        folderDragStarted = false
    }

    private var marqueeRect: CGRect? {
        guard folderDragPaths.isEmpty, marqueeCommitted else { return nil }
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: max(abs(current.x - start.x), 1),
            height: max(abs(current.y - start.y), 1)
        )
    }

    private var listContentHeight: CGFloat {
        ListPaneLayout.totalHeight(rows: layoutRows, entryRowHeight: rowHeight)
    }

    private var listCoordinateSpace: String {
        isSecondary ? "fileListSecondary" : "fileList"
    }

    private func entryAtY(_ y: CGFloat) -> FileEntry? {
        ListPaneLayout.entryAtY(y, rows: layoutRows, entryRowHeight: rowHeight)
    }

    private var marqueeGesture: some Gesture {
        // Nombre/icono → mover (AppKit). Vacío / columnas → marquesina. ⇧ → caja aditiva.
        DragGesture(minimumDistance: PressDragSelectLogic.moveThreshold, coordinateSpace: .named(listCoordinateSpace))
            .onChanged { value in
                if marqueeStart == nil {
                    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let windowPoint = NSApp.currentEvent?.locationInWindow
                    let hit = entryAtY(value.startLocation.y)
                    // Columna Nombre vs columnas meta (marquesina) / huecos de categoría.
                    let inTrailingChrome = value.startLocation.x >= (listContentWidth - trailingColumnsWidth)
                    let inNameColumn = hit != nil && !inTrailingChrome
                    let hitOnName = FileDragArmMonitor.shared.pressArmedFileDrag
                        || (windowPoint.map { FileDragArmMonitor.shared.isNameHit(atWindowPoint: $0) } ?? false)
                        || inNameColumn
                    let hitSelected: Bool = {
                        guard let hit else { return false }
                        return isSecondary
                            ? browser.secondarySelectedIDs.contains(hit.id)
                            : browser.selectedIDs.contains(hit.id)
                    }()
                    let selectedPaths = isSecondary
                        ? browser.secondarySelectedEntries.map(\.path)
                        : browser.selectedEntries.map(\.path)
                    switch PressDragSelectLogic.startAction(
                        hitOnName: hitOnName,
                        hitID: hit?.id,
                        hitPath: hit?.path,
                        hitIsSelected: hitSelected,
                        selectedPaths: selectedPaths,
                        commandHeld: flags.contains(.command),
                        shiftHeld: flags.contains(.shift),
                        hasArmedFileDrag: browser.hasArmedFileDrag,
                        armedPaths: browser.peekArmedFileDrag()
                    ) {
                    case .ignore:
                        return
                    case .beginFileDrag(let paths, let selectOnlyID):
                        if let selectOnlyID {
                            if isSecondary {
                                browser.selectSecondaryOnly(selectOnlyID)
                            } else {
                                browser.selectOnly(selectOnlyID)
                            }
                        }
                        folderDragPaths = paths
                        marqueeStart = value.startLocation
                        marqueeCurrent = value.location
                        // Si AppKit ya armó el press sobre el nombre, él dispara el drag nativo.
                        folderDragStarted = FileDragArmMonitor.shared.pressArmedFileDrag
                        marqueeCommitted = false
                    case .beginMarquee(let additive):
                        marqueeStart = value.startLocation
                        marqueeCurrent = value.location
                        folderDragPaths = []
                        marqueeCommitted = false
                        marqueeStartEntryID = hit?.id
                        marqueeAdditive = additive
                        marqueeBase = additive
                            ? (isSecondary ? browser.secondarySelectedIDs : browser.selectedIDs)
                            : []
                    }
                }

                if !folderDragPaths.isEmpty {
                    let dist = hypot(value.translation.width, value.translation.height)
                    if !folderDragStarted, dist >= PressDragSelectLogic.moveThreshold {
                        folderDragStarted = true
                        FileDragArmMonitor.shared.requestNativeDrag(paths: folderDragPaths)
                    }
                    return
                }

                marqueeCurrent = value.location
                if PressDragSelectLogic.isMarqueeCommitted(translation: value.translation) {
                    if !marqueeCommitted {
                        marqueeCommitted = true
                        if !marqueeAdditive {
                            if isSecondary {
                                browser.clearSecondarySelection()
                            } else {
                                browser.clearSelection()
                            }
                        }
                    }
                    applyMarquee()
                }
            }
            .onEnded { _ in
                if folderDragPaths.isEmpty, marqueeCommitted {
                    applyMarquee()
                }
                resetMarquee()
            }
    }

    private func applyMarquee() {
        guard let start = marqueeStart, let current = marqueeCurrent else { return }
        guard !layoutRows.isEmpty else { return }

        let y0 = min(start.y, current.y)
        let y1 = max(start.y, current.y)
        let contentH = listContentHeight

        if y0 >= contentH {
            if isSecondary {
                browser.applySecondaryMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            } else {
                browser.applyMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            }
            return
        }

        let hits = ListPaneLayout.entryIDs(
            y0: y0,
            y1: min(y1, contentH),
            rows: layoutRows,
            entryRowHeight: rowHeight
        )
        if isSecondary {
            browser.applySecondaryMarqueeSelection(hitIDs: hits, base: marqueeBase, additive: marqueeAdditive)
        } else {
            browser.applyMarqueeSelection(hitIDs: hits, base: marqueeBase, additive: marqueeAdditive)
        }
    }

    private var header: some View {
        // Misma geometría que FileRowButton: Nombre flexible + metas fijas + chrome 28.
        // Sin maxWidth infinity el HStack se queda al ancho intrínseco y las cabeceras
        // quedan a la izquierda mientras las filas sí empujan las columnas a la derecha.
        HStack(spacing: metrics.isCompact ? 8 : 12) {
            Text(L10n.s("Nombre / ruta", "Name / Path"))
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .layoutPriority(1)

            ForEach(visibleListColumns) { column in
                let w = metrics.isCompact ? column.compactWidth : column.width
                if w > 0 {
                    Text(column.shortLabelLocalized)
                        .frame(width: w, alignment: column == .size ? .trailing : .leading)
                        .layoutPriority(0)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Menu {
                ForEach(ListColumn.allCases) { column in
                    Button {
                        browser.toggleListColumn(column)
                    } label: {
                        HStack {
                            Text(column.labelLocalized)
                            if browser.isListColumnVisible(column) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help(L10n.s("Mostrar u ocultar columnas", "Show or hide columns"))
            .padding(.trailing, 10)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, metrics.isCompact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cabecera / hueco de categoría

private struct CategorySectionHeader: View {
    @EnvironmentObject private var browser: BrowserModel
    let category: FileCategory
    let count: Int
    var pane: BrowserModel.PaneFocus = .primary

    var body: some View {
        Button {
            browser.selectVisibleCategory(category, pane: pane)
        } label: {
            HStack(spacing: 8) {
                Text(category.labelLocalized.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OrdenTheme.accent)
                Text("· \(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(L10n.s("clic = todos", "click = all"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(OrdenTheme.accent.opacity(0.08))
        .help(L10n.s("Seleccionar toda la categoría", "Select entire category"))
    }
}

private struct CategoryGapRow: View {
    @EnvironmentObject private var browser: BrowserModel
    let category: FileCategory
    var pane: BrowserModel.PaneFocus = .primary

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                // Hueco: clic = seleccionar el bloque de arriba (categoría).
                browser.selectVisibleCategory(category, pane: pane)
            }
            .help(L10n.s("Hueco: arrastra para marquesina o clic para seleccionar la categoría", "Gap: drag to marquee or click to select the category"))
    }
}

struct FileRowButton: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.ordenMetrics) private var metrics
    let entry: FileEntry
    let zebra: Bool
    var pane: BrowserModel.PaneFocus = .primary
    var columns: [ListColumn] = ListColumn.defaultVisible

    private var isSecondary: Bool { pane == .secondary }

    private var isSelected: Bool {
        isSecondary
            ? browser.secondarySelectedIDs.contains(entry.id)
            : browser.selectedIDs.contains(entry.id)
    }

    private var isCut: Bool {
        browser.isCutPending(path: entry.path)
    }

    var body: some View {
        HStack(alignment: .center, spacing: metrics.isCompact ? 8 : 12) {
            // Solo icono + nombre = zona de MOVER (Finder). El resto de la fila = marquesina.
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    FileTypeIcon(category: entry.category, path: entry.path, size: 17)
                    FileDragArmChrome.Overlay(path: entry.path, size: 26)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: browser.showRowPaths ? 3 : 0) {
                    Text(entry.name)
                        .font(.body.weight(.medium))
                        .lineLimit(metrics.isCompact ? 2 : 1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(isCut ? .secondary : .primary)
                        .strikethrough(isCut)
                    if browser.showRowPaths {
                        Text(entry.path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            }
            // Columna Nombre (icono+texto): jalón = mover. Mínimo sagrado ~220 con icono.
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .padding(.leading, 12)
            .padding(.vertical, metrics.isCompact ? 10 : 8)
            .contentShape(Rectangle())
            .reportFileDragArmFrame(path: entry.path)

            // Columnas meta = vacío Finder (marquesina). Prioridad baja para no robar a Nombre.
            ForEach(columns) { column in
                let w = metrics.isCompact ? column.compactWidth : column.width
                if w > 0 {
                    columnCell(column)
                        .frame(width: w, alignment: column == .size ? .trailing : .leading)
                        .layoutPriority(0)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Button {
                browser.copyPath(entry)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.body)
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(L10n.s("Copiar ruta completa", "Copy full path"))
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { handleRowTap() }
        .opacity(isCut ? 0.42 : 1)
        .background(rowBackground)
        .reportFileRowSelectFrame(path: entry.path)
        .fileDragArmHighlight(path: entry.path)
        .folderDropTarget(entry: entry)
        .fileDragArmPress(entry: entry, browser: browser)
        .contextMenu {
            Button(L10n.s("Abrir", "Open")) {
                ensureSelectedAlone()
                if isSecondary {
                    browser.openSecondaryEntry(entry)
                } else {
                    browser.open(entry)
                }
            }
            OpenWithMenu(entry: entry)
            Button(L10n.s("Obtener información", "Get Info")) {
                ensureSelectedAlone()
                browser.showInfo(entry)
            }
            if entry.isDirectory {
                if browser.isFavorite(entry.path) {
                    Button(L10n.s("Quitar de Favoritos", "Remove from Favorites")) {
                        browser.removeFavorite(entry.path)
                    }
                } else {
                    Button(L10n.s("Añadir a Favoritos", "Add to Favorites")) {
                        browser.addFavorite(entry.path)
                    }
                }
            }
            Button(L10n.s("Renombrar", "Rename")) {
                ensureSelectedAlone()
                browser.promptRename()
            }
            Button(L10n.s("Duplicar", "Duplicate")) {
                ensureInSelection()
                browser.duplicateSelection()
            }
            Button(L10n.s("Comprimir", "Compress")) {
                ensureInSelection()
                browser.compressSelection()
            }
            if ArchiveOps.isExtractable(entry.path) {
                Button(L10n.s("Descomprimir aquí", "Extract here")) {
                    ensureSelectedAlone()
                    browser.extractArchive(entry, intoSecondary: isSecondary)
                }
            }
            Button(L10n.s("A bandeja", "To Tray")) {
                ensureInSelection()
                browser.addSelectionToShelf()
            }
            Button(L10n.s("Vista rápida", "Quick Look")) {
                ensureSelectedAlone()
                browser.openPreviewExplicitly()
            }
            Button(DefaultFileViewerManager.isEnabled ? L10n.s("Abrir carpeta en Finder", "Open folder in Finder") : L10n.s("Mostrar en Finder", "Show in Finder")) { browser.revealInFinder(entry) }
            Button(L10n.s("Copiar", "Copy")) {
                ensureInSelection()
                browser.copySelectionToPasteboard()
            }
            Button(L10n.s("Copiar ruta completa", "Copy Full Path")) { browser.copyPath(entry) }
            if browser.dualPaneEnabled {
                Divider()
                if isSecondary {
                    Button(L10n.s("Mover a Origen", "Move to Origin")) {
                        ensureInSelection()
                        browser.transferSecondarySelectionToPrimary(copy: false)
                    }
                    Button(L10n.s("Copiar a Origen", "Copy to Origin")) {
                        ensureInSelection()
                        browser.transferSecondarySelectionToPrimary(copy: true)
                    }
                } else {
                    Button(L10n.s("Mover a Destino", "Move to Destination")) {
                        ensureInSelection()
                        browser.transferPrimarySelectionToSecondary(copy: false)
                    }
                    Button(L10n.s("Copiar a Destino", "Copy to Destination")) {
                        ensureInSelection()
                        browser.transferPrimarySelectionToSecondary(copy: true)
                    }
                }
            }
            Divider()
            Button(L10n.s("Nueva carpeta aquí", "New Folder here")) {
                browser.focusPane(pane)
                browser.promptNewFolder()
            }
            Button(L10n.s("Nuevo archivo aquí", "New File here")) {
                browser.focusPane(pane)
                browser.promptNewFile()
            }
            Button(L10n.s("Seleccionar todos", "Select All")) {
                if isSecondary {
                    browser.selectAllSecondaryVisible()
                } else {
                    browser.selectAllVisible()
                }
            }
            Button(L10n.s("Quitar selección", "Deselect All")) {
                if isSecondary {
                    browser.clearSecondarySelection()
                } else {
                    browser.clearSelection()
                }
            }
            Divider()
            Button(L10n.s("Mover a la Papelera", "Move to Trash"), role: .destructive) {
                ensureInSelection()
                browser.moveSelectionToTrash()
            }
        }
    }

    private func ensureSelectedAlone() {
        if isSecondary {
            browser.selectSecondaryOnly(entry.id)
        } else {
            browser.selectOnly(entry.id)
        }
    }

    private func ensureInSelection() {
        if isSecondary {
            if !browser.secondarySelectedIDs.contains(entry.id) {
                browser.selectSecondaryOnly(entry.id)
            } else {
                browser.focusPane(.secondary)
            }
        } else if !browser.selectedIDs.contains(entry.id) {
            browser.selectOnly(entry.id)
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return OrdenTheme.rowSelectionFill
        }
        return zebra ? Color.primary.opacity(0.035) : Color.clear
    }

    private var sizeLabel: String {
        if entry.size <= 0 && entry.isDirectory && browser.isMeasuringSizes {
            return "…"
        }
        if entry.size <= 0 && entry.isDirectory {
            return "—"
        }
        return FolderSizer.format(entry.size)
    }

    @ViewBuilder
    private func columnCell(_ column: ListColumn) -> some View {
        switch column {
        case .kind:
            Text(entry.category.labelLocalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .dateAdded:
            dateText(entry.dateAdded)
        case .dateModified:
            dateText(entry.dateModified)
        case .dateCreated:
            dateText(entry.dateCreated)
        case .dateLastOpened:
            dateText(entry.dateLastOpened, allowEmpty: true)
        case .size:
            Text(sizeLabel)
                .font(.caption.monospacedDigit().weight(entry.size > 100_000_000 ? .semibold : .regular))
                .foregroundStyle(entry.size > 500_000_000 ? .orange : .secondary)
        }
    }

    private func dateText(_ date: Date, allowEmpty: Bool = false) -> some View {
        Group {
            if allowEmpty, date == .distantPast {
                Text("—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else {
                Text(date, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 1.er clic → selecciona ya. 2.º clic del mismo doble clic (sin ⌘/⇧) → abre.
    private func handleRowTap() {
        let clicks = FileDragArmMonitor.shared.currentClickCount()
        if clicks == 2 {
            let mods = FileDragArmMonitor.shared.effectiveClickModifiers()
            if !mods.command, !mods.shift {
                ensureSelectedAlone()
                if isSecondary {
                    browser.openSecondaryEntry(entry)
                } else {
                    browser.activateEntry(entry)
                }
                return
            }
        }
        selectRow()
    }

    private func selectRow() {
        browser.isAssistantFocused = false
        // Siempre soltar búsqueda/omnibox: si no, Espacio escribe en el search
        // en vez de abrir Vista rápida (y ⌫/atajos también fallan).
        NSApp.keyWindow?.makeFirstResponder(nil)
        // ⇧ rango · ⌘ suma/quita + naranja · Varios toggle · clic = uno y sale del naranja.
        if isSecondary {
            browser.clickSelectSecondary(entry.id)
        } else {
            browser.clickSelect(entry.id)
        }
    }
}

// MARK: - Toolbar / diálogos (extraídos para el type-checker)

private struct BrowserToolbarModifier: ViewModifier {
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var session: BrowserWindowSession
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: browser.goBack) {
                    Label(L10n.s("Atrás", "Back"), systemImage: "chevron.backward")
                }
                .disabled(!browser.canGoBack)
                .help(L10n.s("Carpeta anterior (⌘1 o ⌥←)", "Previous folder (⌘1 or ⌥←)"))
                .labelStyle(.iconOnly)

                Button(action: browser.goForward) {
                    Label(L10n.s("Adelante", "Forward"), systemImage: "chevron.forward")
                }
                .disabled(!browser.canGoForward)
                .help(L10n.s("Carpeta siguiente (⌘2 o ⌥→)", "Next folder (⌘2 or ⌥→)"))
                .labelStyle(.iconOnly)

                Button(action: browser.goUp) {
                    Label(L10n.s("Arriba", "Enclosing Folder"), systemImage: "chevron.up")
                }
                .help(L10n.s("Carpeta superior (⌘↑)", "Enclosing folder (⌘↑)"))
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    ViewModePicker()
                    PathBreadcrumbBar()
                        .frame(minWidth: 240, maxWidth: 540)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    browser.toggleDualPane()
                } label: {
                    Label(
                        browser.dualPaneEnabled ? L10n.s("1 panel", "1 pane") : L10n.s("2 paneles", "2 panes"),
                        systemImage: "rectangle.split.2x1"
                    )
                }
                .labelStyle(.iconOnly)
                .help(
                    browser.dualPaneEnabled
                        ? L10n.s("Volver a un solo panel · ⌘⇧D", "Return to single pane · ⌘⇧D")
                        : L10n.s("Dos paneles · ⌘⇧D", "Dual panes · ⌘⇧D")
                )
                .tint(browser.dualPaneEnabled ? OrdenTheme.accent : nil)

                Button {
                    browser.showAssistantPanel.toggle()
                } label: {
                    Label(L10n.s("IA", "AI"), systemImage: "sparkles")
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(browser.showAssistantPanel ? OrdenTheme.accentSecondary : .primary)
                .help(L10n.s("Asistente IA local · ⌘5", "Local AI assistant · ⌘5"))

                Menu {
                    Button {
                        session.addTab()
                    } label: {
                        Label(L10n.s("Nueva pestaña", "New Tab"), systemImage: "plus.square.on.square")
                    }
                    .keyboardShortcut("t", modifiers: .command)

                    Button {
                        openWindow(id: "browser")
                    } label: {
                        Label(L10n.s("Nueva ventana", "New Window"), systemImage: "macwindow.badge.plus")
                    }

                    Divider()

                    Menu(L10n.s("Tema de color", "Color Theme")) {
                        ColorThemeMenuContent()
                    }

                    Divider()

                    Toggle(
                        L10n.s("Mostrar ocultos", "Show Hidden"),
                        isOn: Binding(
                            get: { browser.showHiddenFiles },
                            set: { browser.setShowHiddenFiles($0) }
                        )
                    )
                    Toggle(
                        L10n.s("Mostrar rutas bajo el nombre", "Show paths under name"),
                        isOn: Binding(
                            get: { browser.showRowPaths },
                            set: { browser.setShowRowPaths($0) }
                        )
                    )
                    Toggle(
                        L10n.s("Selección múltiple por clic", "Multi-select by click"),
                        isOn: $browser.multiSelectMode
                    )

                    Divider()

                    Button {
                        browser.openTerminalHere()
                    } label: {
                        Label(L10n.s("Abrir en Terminal", "Open in Terminal"), systemImage: "terminal")
                    }

                    Button {
                        browser.reloadFromUser()
                    } label: {
                        Label(L10n.s("Actualizar", "Refresh"), systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                } label: {
                    Label(L10n.s("Más opciones", "More Options"), systemImage: "ellipsis.circle")
                }
                .help(L10n.s("Más opciones", "More options"))
                .labelStyle(.iconOnly)
            }
        }
    }
}

/// Toggle de toolbar con estado visual claro: ON = acento + símbolo filled; OFF = apagado.
private struct ToolbarStateToggle: View {
    @Binding var isOn: Bool
    let title: String
    let onSymbol: String
    let offSymbol: String
    let helpOn: String
    let helpOff: String

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: isOn ? onSymbol : offSymbol)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .tint(isOn ? OrdenTheme.accent : .secondary)
        .foregroundStyle(isOn ? OrdenTheme.accent : Color.secondary.opacity(0.85))
        .help(isOn ? helpOn : helpOff)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

private struct BrowserDialogsModifier: ViewModifier {
    @EnvironmentObject private var browser: BrowserModel
    let shortPath: (String) -> String

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $browser.showNewFolderDialog) {
                NamePromptSheet(kind: .newFolder)
                    .environmentObject(browser)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $browser.showNewFileDialog) {
                NamePromptSheet(kind: .newFile)
                    .environmentObject(browser)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $browser.showRenameDialog) {
                NamePromptSheet(kind: .rename)
                    .environmentObject(browser)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $browser.showGoToFolderDialog) {
                GoToFolderSheet()
                    .environmentObject(browser)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $browser.showDeepSearchDialog) {
                DeepSearchSheet()
                    .environmentObject(browser)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $browser.showOllamaSetupDialog) {
                OllamaSetupSheet()
                    .environmentObject(browser)
            }
            .sheet(isPresented: $browser.showFolderHandlerSetupDialog) {
                FolderHandlerSetupSheet(result: browser.folderHandlerSetupResult)
                    .environmentObject(browser)
            }
            .sheet(isPresented: $browser.showSaveTemplateDialog) {
                SaveTemplateSheet()
                    .environmentObject(browser)
            }
            .sheet(item: $browser.smartFolderDraft) { draft in
                SmartFolderSheet(initial: draft, isNew: browser.smartFolderDraftIsNew)
                    .environmentObject(browser)
            }
            .sheet(item: $browser.pendingMergePreview) { preview in
                MergePreviewSheet(preview: preview)
                    .environmentObject(browser)
            }
            .sheet(isPresented: $browser.showLicenseSheet) {
                FindaroLicenseSheet()
            }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var browser: BrowserModel
    @StateObject private var ollama = OllamaClient.shared
    @StateObject private var licenseStore = LicenseStore.shared
    @State private var editingShortcut: AssistantShortcut?
    @State private var showNewShortcut = false
    @State private var editingHotkey: AppHotkeyDefinition?
    @State private var licenseInput: String = ""
    @State private var licenseActionError: String?
    @State private var showDeactivateConfirm: Bool = false

    var body: some View {
        TabView {
            settingsGeneral
                .tabItem { Label(L10n.s("General", "General"), systemImage: "slider.horizontal.3") }
            settingsAssistant
                .tabItem { Label(L10n.s("Asistente", "Assistant"), systemImage: "sparkles") }
            settingsShortcuts
                .tabItem { Label(L10n.s("Atajos", "Shortcuts"), systemImage: "keyboard") }
            settingsSearch
                .tabItem { Label(L10n.s("Búsqueda", "Search"), systemImage: "magnifyingglass") }
            settingsMaintenance
                .tabItem { Label(L10n.s("Mantenimiento", "Maintenance"), systemImage: "wrench.and.screwdriver") }
            settingsLicense
                .tabItem { Label(L10n.s("Licencia", "License"), systemImage: "key.fill") }
        }
        .padding(.top, 10)
        .frame(width: 560, height: 520)
        .sheet(isPresented: $browser.showOllamaSetupDialog) {
            OllamaSetupSheet()
                .environmentObject(browser)
        }
        .sheet(isPresented: $browser.showFolderHandlerSetupDialog) {
            FolderHandlerSetupSheet(result: browser.folderHandlerSetupResult)
                .environmentObject(browser)
        }
        .sheet(isPresented: $showNewShortcut) {
            ShortcutEditorSheet(existing: nil) { shortcut in
                _ = browser.addAssistantShortcut(shortcut)
            }
        }
        .sheet(item: $editingShortcut) { shortcut in
            ShortcutEditorSheet(existing: shortcut) { updated in
                browser.updateAssistantShortcut(updated)
            }
        }
        .sheet(item: $editingHotkey) { def in
            HotkeyRecorderSheet(
                definition: def,
                current: browser.chord(forHotkey: def.id) ?? def.defaultChord
            )
            .environmentObject(browser)
        }
        .task {
            ollama.applyPreferences(browser.store.preferences)
            await ollama.probe()
        }
    }

    // MARK: General

    private var settingsGeneral: some View {
        Form {
            Section {
                settingsRow(
                    icon: "globe",
                    tint: .blue,
                    title: L10n.s("Idioma de la interfaz", "Interface Language"),
                    subtitle: L10n.s("Español, English o según tu Mac", "Spanish, English, or matching your Mac")
                ) {
                    Picker(L10n.s("Idioma", "Language"), selection: Binding(
                        get: { browser.appLanguage },
                        set: { browser.setAppLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.menuLabel).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 160, idealWidth: 180)
                }

                settingsRow(
                    icon: "paintpalette.fill",
                    tint: OrdenTheme.accent,
                    title: L10n.s("Tema de color", "Color Theme"),
                    subtitle: L10n.s("Cambia al instante en todas las ventanas", "Changes instantly across all windows")
                ) {
                    ColorThemeSwatchPicker()
                }

                settingsRow(
                    icon: "keyboard",
                    tint: OrdenTheme.accent,
                    title: L10n.s("Atajo global", "Global Hotkey"),
                    subtitle: L10n.s("Abre Findaro en «\(browser.globalHotkeyFolderDisplayName)»", "Opens Findaro in «\(browser.globalHotkeyFolderDisplayName)»")
                ) {
                    HStack(spacing: 6) {
                        let globalChord = browser.chord(forHotkey: "nav.globalOpen")
                            ?? KeyChord(keyCode: 0, character: "a", option: true, control: true)
                        Button {
                            if let def = AppHotkeyCatalog.definition(id: "nav.globalOpen") {
                                editingHotkey = def
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(globalChord.displayLabel)
                                    .font(.title3.monospaced().weight(.bold))
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(OrdenTheme.accent.opacity(0.18), in: Capsule())
                            .foregroundStyle(OrdenTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.s("Cambiar teclas del atajo global", "Change global hotkey"))

                        Button {
                            browser.pickGlobalHotkeyFolder()
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.title3)
                                .foregroundStyle(OrdenTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.s("Elegir carpeta que abre el atajo", "Choose folder to open with hotkey"))

                        if browser.usesCustomGlobalHotkeyFolder {
                            Button {
                                browser.resetGlobalHotkeyFolder()
                            } label: {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.s("Volver a Descargas", "Reset to Downloads"))
                        }
                    }
                }

                settingsRow(
                    icon: "folder.badge.gearshape",
                    tint: .orange,
                    title: L10n.s("Abrir carpetas con Findaro", "Open folders with Findaro"),
                    subtitle: OpenFolderBridge.isDefaultFolderHandler()
                        ? L10n.s("Findaro es la app por defecto", "Findaro is default folder handler")
                        : L10n.s("macOS obliga un paso manual (Abrir con → Siempre)", "macOS requires manual step (Open With → Always)")
                ) {
                    Button(OpenFolderBridge.isDefaultFolderHandler() ? L10n.s("Ver cómo", "See how") : L10n.s("Preparar…", "Setup…")) {
                        browser.runFolderHandlerSetup()
                    }
                }

                settingsRow(
                    icon: "macwindow.and.cursorarrow",
                    tint: .teal,
                    title: L10n.s("Usar Findaro en lugar de Finder para “Mostrar en Finder”", "Use Findaro instead of Finder for “Show in Finder”"),
                    subtitle: L10n.s("Cuando otra app pida mostrar un archivo, se abrirá en Findaro. El escritorio, la Papelera, el Dock y las ventanas de Guardar/Abrir siguen siendo de macOS. Puedes desactivarlo cuando quieras.", "When another app asks to show a file, it will open in Findaro. Desktop, Trash, Dock and Save/Open windows remain macOS. You can disable it anytime.")
                ) {
                    Toggle("", isOn: Binding(
                        get: { DefaultFileViewerManager.isEnabled },
                        set: { newValue in
                            if newValue {
                                _ = DefaultFileViewerManager.enable()
                            } else {
                                _ = DefaultFileViewerManager.disable()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                }
            } header: {
                Text(L10n.s("Inicio rápido", "Quick Start"))
            } footer: {
                Text(L10n.s("Lapicito = cambiar teclas · carpeta = a dónde abre. «Abrir con → Siempre» es aparte.", "Pencil = change keys · folder = open location. «Open With → Always» is separate."))
            }

            Section {
                settingsRow(
                    icon: "arrow.up.arrow.down",
                    tint: OrdenTheme.accent,
                    title: L10n.s("Orden de esta sesión", "Sort Order for Session"),
                    subtitle: browser.rule.summaryLocalized
                ) {
                    Text(browser.scopeBadge)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: Binding(
                    get: { browser.explorerKeyboardProfile },
                    set: { browser.setExplorerKeyboardProfile($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.s("Teclado tipo Explorer", "Explorer Keyboard Profile"))
                        Text(L10n.s("Enter abre · F2 renombra (si no, Enter renombra como Finder)", "Enter opens · F2 renames (otherwise Enter renames like Finder)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { browser.showHiddenFiles },
                    set: { browser.setShowHiddenFiles($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.s("Mostrar ocultos", "Show Hidden Files"))
                        Text(L10n.s("Archivos con punto o flag hidden · ⌘⇧.", "Files starting with dot or hidden flag · ⌘⇧."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { browser.flattenFolderView },
                    set: { browser.setFlattenFolderView($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.s("Vista plana", "Flat Folder View"))
                        Text(L10n.s("Lista archivos de subcarpetas sin jerarquía", "Lists files in subfolders without hierarchy"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L10n.s("Lista de archivos", "File List"))
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: Asistente

    private var settingsAssistant: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill((ollama.isReady ? Color.green : OrdenTheme.accent).opacity(0.18))
                            .frame(width: 52, height: 52)
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(ollama.isReady ? .green : OrdenTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s("Inteligencia local", "On-Device AI"))
                            .font(.headline)
                        Text(ollamaStatusLabel)
                            .font(.subheadline)
                            .foregroundStyle(ollama.isReady ? .green : .secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)

                Button {
                    browser.showOllamaSetupDialog = true
                } label: {
                    Label(L10n.s("Configurar / detectar Ollama…", "Configure / detect Ollama…"), systemImage: "waveform.badge.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.large)
            } header: {
                Text(L10n.s("Ollama (opcional)", "Ollama (Optional)"))
            } footer: {
                Text(L10n.s("Si no quieres IA, no pasa nada: el asistente sigue con atajos y reglas. Nada se sube a internet.", "If you don't want AI, shortcuts and rules still work. Nothing is uploaded to internet."))
            }

            Section {
                tipLine(
                    icon: "mic.circle.fill",
                    title: L10n.s("Voz (mantener micrófono)", "Voice (hold microphone)"),
                    detail: L10n.s("En el asistente: mantén, habla, suelta. Local en tu Mac.", "In the assistant: hold, speak, release. Local on your Mac.")
                )
                Button(L10n.s("Abrir asistente (⌘5)", "Open assistant (⌘5)")) {
                    browser.showAssistantPanel = true
                }
                Text(L10n.s("Los atajos se editan en la pestaña Atajos.", "Shortcuts are edited in the Shortcuts tab."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.s("Panel y voz", "Panel and voice"))
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: Atajos

    private var settingsShortcuts: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.s(
                            "\(AppHotkeyCatalog.catalog.count) atajos de teclado",
                            "\(AppHotkeyCatalog.catalog.count) keyboard shortcuts"
                        ))
                        .font(.body.weight(.semibold))
                        Text(L10n.s(
                            "Incluye Actualizar ⌘R, Renombrar ⌃R, Papelera ⌫, Esc Esc bandeja y el resto.",
                            "Includes Refresh ⌘R, Rename ⌃R, Trash ⌫, Esc Esc tray, and the rest."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.s("Restaurar teclado", "Restore Shortcuts")) {
                        browser.restoreDefaultKeyboardHotkeys()
                    }
                    .buttonStyle(.bordered)
                }
            }

            ForEach(AppHotkeyGroup.allCases, id: \.self) { group in
                let items = AppHotkeyCatalog.catalog.filter { $0.group == group }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { def in
                            keyboardHotkeyRow(def)
                        }
                    } header: {
                        Text("\(group.titleLocalized) · \(items.count)")
                    } footer: {
                        if group == .view {
                            Text(L10n.s(
                                "Clic en una fila para cambiar la tecla. Reinicia Findaro si el menú de macOS no se actualiza.",
                                "Click a row to change the key. Relaunch Findaro if the macOS menu does not refresh."
                            ))
                        }
                    }
                }
            }

            Section {
                ForEach(browser.assistantShortcuts) { shortcut in
                    shortcutSettingsRow(shortcut)
                }
                .onMove(perform: browser.moveAssistantShortcut)
                .onDelete { indexSet in
                    let ids = indexSet.map { browser.assistantShortcuts[$0].id }
                    for id in ids {
                        browser.deleteAssistantShortcut(id: id)
                    }
                }

                Button {
                    showNewShortcut = true
                } label: {
                    Label(L10n.s("Nuevo filtro", "New Filter"), systemImage: "plus")
                }
                .disabled(browser.assistantShortcuts.count >= AssistantShortcut.maxCount)
            } header: {
                HStack {
                    Text(L10n.s("Filtros del asistente", "Assistant Filters"))
                    Spacer()
                    Text("\(browser.assistantShortcuts.count)/\(AssistantShortcut.maxCount)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                HStack {
                    Button(L10n.s("Restaurar filtros", "Restore Filters")) {
                        browser.restoreDefaultAssistantShortcuts()
                    }
                    Spacer()
                    Text(L10n.s("Imágenes de hoy, docs de ayer…", "Today's images, yesterday's docs…"))
                }
            }
        }
        .listStyle(.inset)
    }

    private func keyboardHotkeyRow(_ def: AppHotkeyDefinition) -> some View {
        let chord = browser.chord(forHotkey: def.id) ?? def.defaultChord
        let customized = browser.keyboardHotkeyOverrides[def.id] != nil
        return Button {
            guard def.isEditable else { return }
            editingHotkey = def
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(def.titleLocalized)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(def.detailLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(chord.displayLabel)
                    .font(.title3.monospaced().weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        (customized ? OrdenTheme.accent.opacity(0.22) : OrdenTheme.panelFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .foregroundStyle(customized ? OrdenTheme.accent : .primary)
                if def.isEditable {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundStyle(OrdenTheme.accent)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if def.isEditable {
                Button(L10n.s("Cambiar…", "Change…")) { editingHotkey = def }
                Button(L10n.s("Restablecer", "Reset")) { browser.resetKeyboardHotkey(def.id) }
                    .disabled(!customized)
            }
        }
        .help(def.isEditable ? L10n.s("Clic para cambiar", "Click to change") : L10n.s("Atajo del sistema (no editable aquí)", "System shortcut (not editable here)"))
    }

    private func shortcutSettingsRow(_ shortcut: AssistantShortcut) -> some View {
        Button {
            editingShortcut = shortcut
        } label: {
            HStack(spacing: 12) {
                Image(systemName: shortcutSettingsIcon(shortcut))
                    .font(.title3)
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(shortcut.displayTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(shortcutSubtitle(shortcut))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.s("Editar", "Edit")) { editingShortcut = shortcut }
            Button(L10n.s("Usar ahora", "Use Now")) {
                browser.showAssistantPanel = true
                browser.applyAssistantShortcut(shortcut)
            }
            Divider()
            Button(L10n.s("Borrar", "Delete"), role: .destructive) {
                browser.deleteAssistantShortcut(id: shortcut.id)
            }
        }
    }

    private func shortcutSettingsIcon(_ shortcut: AssistantShortcut) -> String {
        if shortcut.categories == AssistantShortcut.documentCategories { return "doc.text" }
        return shortcut.categories.first?.symbolName ?? "line.3.horizontal.decrease.circle"
    }

    private func shortcutSubtitle(_ shortcut: AssistantShortcut) -> String {
        let type: String
        if shortcut.categories == AssistantShortcut.documentCategories {
            type = L10n.s("Documentos", "Documents")
        } else if shortcut.categories.isEmpty {
            type = L10n.s("Cualquier tipo", "Any Type")
        } else if shortcut.categories.count == 1, let only = shortcut.categories.first {
            type = only.labelLocalized
        } else {
            type = "\(shortcut.categories.count) " + L10n.s("tipos", "types")
        }
        return "\(type) · \(shortcut.dateWindow.labelLocalized)"
    }

    // MARK: Búsqueda

    private var settingsSearch: some View {
        Form {
            Section {
                tipLine(icon: "doc.text.magnifyingglass", title: L10n.s("Filtro de arriba", "Top Filter"), detail: L10n.s("Solo nombres en esta carpeta", "Only file names in current folder"))
                tipLine(icon: "magnifyingglass.circle.fill", title: L10n.s("Subcarpetas · ⌘4", "Subfolders · ⌘4"), detail: L10n.s("Esta carpeta y todo lo de adentro", "Current folder and all nested contents"))
                tipLine(icon: "checkmark.circle.fill", title: L10n.s("Coincide por parte del nombre", "Matches partial file names"), detail: L10n.s("vibe encuentra vibesystems…", "e.g. vibe matches vibesystems…"))
                tipLine(icon: "xmark.circle.fill", title: L10n.s("No lee el contenido", "Does not read file content"), detail: L10n.s("Eso es del asistente / Ollama", "Use AI Assistant / Ollama for content queries"))
            } header: {
                Text(L10n.s("Cómo busca Findaro", "How Findaro Searches"))
            } footer: {
                Text(L10n.s("Sin comodines (* ?) y sin Spotlight. El asistente (⌘5) es aparte.", "No wildcard syntax required and no Spotlight indexing lag. Assistant (⌘5) handles deep natural queries."))
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: Mantenimiento

    private var settingsMaintenance: some View {
        Form {
            Section {
                settingsRow(
                    icon: "app.badge",
                    tint: OrdenTheme.accent,
                    title: L10n.s("Versión", "Version"),
                    subtitle: "findaro.iareal.net"
                ) {
                    Text(AppUpdateChecker.currentVersion())
                        .font(.body.monospaced().weight(.semibold))
                }
                Button {
                    Task { await AppUpdateChecker.shared.check(interactive: true) }
                } label: {
                    Label(L10n.s("Buscar actualizaciones…", "Check for Updates…"), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } header: {
                Text(L10n.s("Actualizaciones", "Updates"))
            }

            Section {
                Button(role: .none) {
                    ThumbnailStore.shared.clearAll()
                    browser.reload()
                    browser.statusMessage = L10n.s("Caché de miniaturas limpia", "Thumbnail cache cleared")
                } label: {
                    Label(L10n.s("Limpiar miniaturas", "Clear Thumbnails"), systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } header: {
                Text(L10n.s("Caché", "Cache"))
            } footer: {
                Text(L10n.s("Si un icono de vídeo o imagen se ve raro, limpia aquí. Al actualizar la app también se limpia.", "If an image or video preview appears corrupted, clear cache here."))
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var ollamaStatusLabel: String {
        if ollama.isReady { return L10n.s("Activo · \(ollama.selectedModel)", "Active · \(ollama.selectedModel)") }
        if ollama.enabled && !ollama.available { return L10n.s("Activado, pero Ollama no responde", "Enabled, but Ollama is not responding") }
        if ollama.available { return L10n.s("Detectado — aún no activado", "Detected — not enabled yet") }
        return L10n.s("Apagado · solo reglas y atajos", "Off · rules & shortcuts only")
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 2)
    }

    private func tipLine(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(OrdenTheme.accent)
                .frame(width: 28, height: 28)
                .background(OrdenTheme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Licencia

    /// Etiqueta de plan: solo=Personal(1), personal=Pro(2), family=Familiar(5).
    private static func licensePlanLabel(tier: String, seats: Int) -> String {
        switch tier {
        case "family":
            return L10n.s("Familiar / Studio (hasta 5 Macs)", "Family / Studio (up to 5 Macs)")
        case "solo":
            return L10n.s("Personal (1 Mac)", "Personal (1 Mac)")
        default:
            if seats == 1 {
                return L10n.s("Personal (1 Mac)", "Personal (1 Mac)")
            }
            return L10n.s("Pro (hasta 2 Macs)", "Pro (up to 2 Macs)")
        }
    }

    private static func licenseSeatsLabel(activeCount: Int, seats: Int) -> String {
        if seats == 1 {
            return L10n.s("\(activeCount) de 1 Mac registrada", "\(activeCount) of 1 Mac registered")
        }
        return L10n.s("\(activeCount) de \(seats) Macs registradas", "\(activeCount) of \(seats) Macs registered")
    }

    private var settingsLicense: some View {
        Form {
            Section {
                switch licenseStore.state {
                case .proActive(let key, let tier, let seats, let activeCount):
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title)
                                .foregroundStyle(Color.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FINDARO PRO")
                                    .font(.headline.weight(.bold))
                                Text(L10n.s("Licencia de por vida activa en este equipo", "Lifetime license active on this device"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        HStack {
                            Text(L10n.s("Plan:", "Plan:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Self.licensePlanLabel(tier: tier, seats: seats))
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text(L10n.s("Equipos activos:", "Active devices:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Self.licenseSeatsLabel(activeCount: activeCount, seats: seats))
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text(L10n.s("Clave:", "Key:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(key)
                                .font(.system(.body, design: .monospaced))
                        }

                        HStack {
                            Text(L10n.s("ID de Hardware (este Mac):", "Hardware ID (this Mac):"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(HardwareID.current())
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        HStack {
                            Spacer()
                            Button(L10n.s("Desactivar esta Mac", "Deactivate this Mac"), role: .destructive) {
                                showDeactivateConfirm = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 6)

                case .trial(let daysRemaining, let expiresAt):
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.title)
                                .foregroundStyle(Color.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.s("Período de prueba activo", "Free trial active"))
                                    .font(.headline.weight(.bold))
                                Text(L10n.s("\(daysRemaining) días restantes (hasta el \(expiresAt.formatted(date: .abbreviated, time: .shortened)))", "\(daysRemaining) days remaining (until \(expiresAt.formatted(date: .abbreviated, time: .shortened)))"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(L10n.s("Disfruta de todas las funciones de Findaro. Cuando estés listo, adquiere tu licencia de por vida.", "Enjoy all Findaro features without limits. When ready, upgrade to a lifetime license."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button {
                                if let url = URL(string: "https://findaro.iareal.net/comprar") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label(L10n.s("Comprar licencia (desde $29 USD)", "Buy License (from $29 USD)"), systemImage: "cart.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OrdenTheme.accent)
                        }
                    }
                    .padding(.vertical, 6)

                case .trialExpired:
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "hourglass.bottomhalf.filled")
                                .font(.title)
                                .foregroundStyle(Color.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.s("Prueba de 14 días finalizada", "14-day trial expired"))
                                    .font(.headline.weight(.bold))
                                Text(L10n.s("Adquiere tu licencia de por vida para seguir usando Findaro.", "Purchase your lifetime license to continue using Findaro."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Button {
                                if let url = URL(string: "https://findaro.iareal.net/comprar") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Label(L10n.s("Comprar licencia de por vida (desde $29 USD)", "Buy lifetime license (from $29 USD)"), systemImage: "cart.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OrdenTheme.accent)
                        }
                    }
                    .padding(.vertical, 6)

                case .revoked(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundStyle(Color.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.s("Licencia no válida o revocada", "Invalid or revoked license"))
                                    .font(.headline.weight(.bold))
                                Text(message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text(L10n.s("Estado de activación", "Activation Status"))
            }

            if !licenseStore.state.isPro {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.s("Si ya compraste tu licencia o recibiste una clave, ingrésala a continuación:", "If you purchased a license or received a key, enter it below:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("", text: $licenseInput, prompt: Text("FINDARO-XXXX-XXXX-XXXX-XXXX"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            Button {
                                Task {
                                    do {
                                        licenseActionError = nil
                                        try await licenseStore.activate(key: licenseInput)
                                        licenseInput = ""
                                    } catch {
                                        licenseActionError = error.localizedDescription
                                    }
                                }
                            } label: {
                                if licenseStore.isBusy {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(L10n.s("Activar", "Activate"))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OrdenTheme.accent)
                            .disabled(licenseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licenseStore.isBusy)
                        }

                        if let err = licenseActionError ?? licenseStore.lastErrorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(L10n.s("Activar con clave", "Activate with Key"))
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.s("• Personal: 1 Mac por $29 USD (pago único de por vida).", "• Personal: 1 Mac for $29 USD (one-time lifetime payment)."))
                    Text(L10n.s("• Pro: 2 Macs por $39 USD (ideal escritorio + MacBook).", "• Pro: 2 Macs for $39 USD (ideal for desktop + MacBook)."))
                    Text(L10n.s("• Familiar / Studio: 5 Macs por $59 USD.", "• Family / Studio: 5 Macs for $59 USD."))
                    Text(L10n.s("• Validación offline: tu licencia funciona permanentemente sin requerir conexión constante a internet.", "• Offline validation: your license works offline without requiring constant internet connection."))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(L10n.s("Información de licenciamiento", "Licensing Information"))
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .confirmationDialog(L10n.s("¿Desactivar esta Mac?", "Deactivate this Mac?"), isPresented: $showDeactivateConfirm) {
            Button(L10n.s("Desactivar esta Mac", "Deactivate this Mac"), role: .destructive) {
                Task {
                    try? await licenseStore.deactivate()
                }
            }
            Button(L10n.s("Cancelar", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.s("Esta Mac dejará de tener la licencia activa y se liberará el asiento para otro equipo.", "This Mac will no longer have an active license, freeing up a seat for another Mac."))
        }
    }
}

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

    /// REGLA: el menú izquierdo NUNCA se colapsa; el ancho sí se adapta a la pantalla.
    private var sidebarWidth: CGFloat { metrics.sidebarWidth }
    private var detailMinWidth: CGFloat { metrics.detailMinWidth }
    private var assistantWidth: CGFloat { metrics.assistantWidth }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)
                .frame(minWidth: sidebarWidth, idealWidth: sidebarWidth, maxWidth: sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
                .background(OrdenTheme.sidebarFill)
                .accessibilityLabel("Menú lateral")
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
                }
            )
        )
        .readLayoutWidth { w in
            applyWindowSize(CGSize(width: w, height: windowHeight))
        }
        .onAppear {
            OrdenWindowFit.applyToOpenWindows()
            metrics = .resolve(windowSize: CGSize(width: windowWidth, height: windowHeight))
        }
        .searchable(
            text: $browser.searchText,
            placement: .toolbar,
            prompt: "Buscar en Findaro…"
        )
        .onSubmit(of: .search) {
            browser.startDeepSearch()
        }
        .onAppear { SelectionCancelMonitor.install(browser: browser, session: session) }
        .onDisappear { SelectionCancelMonitor.remove() }
        .modifier(BrowserToolbarModifier())
        .modifier(BrowserDialogsModifier(shortPath: shortPath))
        .onKeyPress(.space) {
            guard !browser.hasModalSheet else { return .ignored }
            // No robar el espacio del chat / omnibox / cualquier campo de texto.
            if FindaroTextInput.isEditing { return .ignored }
            browser.quickLookSelection()
            return .handled
        }
        .onKeyPress(keys: [.downArrow], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            guard !browser.hasModalSheet else { return .ignored }
            browser.openSelection()
            return .handled
        }
        .onKeyPress(keys: [.delete], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            guard !browser.hasModalSheet else { return .ignored }
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
            browser.cancelSelection()
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

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            SortBar()
                .fixedSize(horizontal: false, vertical: true)
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

            FileActionsBar()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            FileDragArmChrome.ReadyBanner()
                .fixedSize(horizontal: false, vertical: true)

            if browser.showDeepSearchPanel {
                RecursiveSearchPanel()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if browser.hasActiveViewFilters {
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
                                    if browser.focusedPane == .primary {
                                        FindaroStatusPill(title: L10n.s("activo", "active"), kind: .processing)
                                    }
                                    Spacer(minLength: 4)
                                    if browser.focusedPane != .primary {
                                        Button {
                                            browser.focusOriginPane()
                                        } label: {
                                            Label(L10n.s("Activar", "Activate"), systemImage: "arrow.left.circle.fill")
                                                .font(.caption.weight(.semibold))
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
                                    // Solo acciones hacia Destino (→). «← Mover / ← Copiar» viven en Destino.
                                    Button {
                                        browser.transferPrimarySelectionToSecondary(copy: false)
                                    } label: {
                                        Label(L10n.s("Mover →", "Move →"), systemImage: "arrow.right.circle.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .controlSize(.small)
                                    .help(L10n.s("Mueve lo seleccionado aquí → Destino · ⌘⇧M", "Move selection here → Destination · ⌘⇧M"))
                                    Button {
                                        browser.transferPrimarySelectionToSecondary(copy: true)
                                    } label: {
                                        Text(L10n.s("Copiar →", "Copy →"))
                                            .font(.caption.weight(.semibold))
                                    }
                                    .controlSize(.small)
                                    .help(L10n.s("Copia lo seleccionado aquí → Destino", "Copy selection here → Destination"))
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
                    .help("Cerrar aviso")
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

    private var filterSummary: String {
        var parts: [String] = []
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

// MARK: - Stats / cleanup

struct FolderStatsBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Segmentos clicables: Downloads → va a Downloads, etc.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(browser.pathSegments.enumerated()), id: \.element.id) { index, segment in
                            if index > 0 {
                                Text("/")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Button {
                                browser.navigate(to: segment.path)
                            } label: {
                                Text(segment.title)
                                    .font(.system(.caption, design: .monospaced).weight(
                                        index == browser.pathSegments.count - 1 ? .semibold : .regular
                                    ))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(index == browser.pathSegments.count - 1 ? .primary : OrdenTheme.accent)
                            .help(L10n.s("Ir a \(segment.path)", "Go to \(segment.path)"))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    browser.copyCurrentFolderPath()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(L10n.s("Copiar ruta completa", "Copy full path"))
                Label(browser.folderTotalLabel, systemImage: "externaldrive.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                if browser.isMeasuringSizes {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(
                    browser.downloadsTodayMode
                        ? "· \(browser.visibleEntries.count) " + L10n.s("de hoy", "today") + " / \(browser.entries.count)"
                        : "· \(browser.entries.count) " + L10n.s("elementos", "items")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let shortcut = browser.activeAssistantShortcut {
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

            // Solo con orden por peso — evita una segunda franja permanente
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                FindaroMark(size: 30, showWordmark: true, wordmarkSize: 14, compact: false)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                favoritesDropZone

                sectionHeader(L10n.s("Ubicaciones", "Locations"))
                    .padding(.top, 12)
                ForEach(locationItems) { item in
                    sidebarButton(item, isFavoriteSlot: false)
                }
            }
            .padding(.bottom, 16)
            // volumesTick fuerza recalcular locationItems al conectar USB/discos
            .id(volumesTick)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrdenTheme.sidebarFill)
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

    private var favoriteItems: [SidebarItem] {
        browser.store.preferences.favorites.map { path in
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
            trashPath: TrashOps.userTrashPath
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

    private func isActive(_ path: String) -> Bool {
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

// MARK: - File pane (clic + marquee; sin GeometryReader = sin hueco)

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

    private var paneAllSelected: Bool {
        isSecondary ? browser.allSecondarySelected : browser.allVisibleSelected
    }

    /// Debe coincidir con la altura fija de cada `FileRowButton`.
    private var rowHeight: CGFloat {
        // Respetar el toggle «Rutas» siempre (antes se ocultaban en compacto y el botón “no servía”).
        let base = PressDragSelectLogic.listRowHeight(showPaths: browser.showRowPaths)
        // En compacto el nombre puede ocupar 2 líneas.
        return metrics.isCompact ? max(base, browser.showRowPaths ? 72 : 52) : base
    }

    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBase: Set<String> = []
    @State private var marqueeAdditive = false
    @State private var marqueeCommitted = false
    @State private var marqueeStartEntryID: String?
    @State private var folderDragPaths: [String] = []
    @State private var folderDragStarted = false

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
                        ForEach(Array(paneEntries.enumerated()), id: \.element.id) { index, entry in
                            FileRowButton(entry: entry, zebra: index.isMultiple(of: 2), pane: pane)
                                .frame(height: rowHeight)
                                .id(entry.id)
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
                    .gesture(marqueeGesture)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        CGFloat(paneEntries.count) * rowHeight
    }

    private var listCoordinateSpace: String {
        isSecondary ? "fileListSecondary" : "fileList"
    }

    private func entryAtY(_ y: CGFloat) -> FileEntry? {
        let entries = paneEntries
        guard let idx = RowHitTestLogic.indexAtY(y, rowHeight: rowHeight, count: entries.count) else {
            return nil
        }
        return entries[idx]
    }

    private var marqueeGesture: some Gesture {
        // minimumDistance > 0: el clic limpio llega al botón (1 archivo).
        // Marquee solo tras rectángulo intencional (marqueeCommitSize).
        DragGesture(minimumDistance: PressDragSelectLogic.moveThreshold, coordinateSpace: .named(listCoordinateSpace))
            .onChanged { value in
                if marqueeStart == nil {
                    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    // ⌘ es modo naranja (suma/quita 1), NUNCA marquee — eso seleccionaba vecinos.
                    if flags.contains(.command), !browser.hasArmedFileDrag {
                        return
                    }
                    // Con modo naranja: arrastre mueve archivos (no marquee)
                    if browser.hasArmedFileDrag {
                        marqueeStart = value.startLocation
                        marqueeCurrent = value.location
                        folderDragPaths = browser.peekArmedFileDrag()
                        folderDragStarted = false
                        return
                    }
                    if browser.fileDragArmingPath != nil {
                        return
                    }

                    // Arrastre sobre fila ya seleccionada: arrastre nativo inmediato de los archivos seleccionados
                    if let entry = entryAtY(value.startLocation.y) {
                        let isSelected = isSecondary
                            ? browser.secondarySelectedIDs.contains(entry.id)
                            : browser.selectedIDs.contains(entry.id)
                        if isSelected {
                            folderDragPaths = isSecondary
                                ? browser.secondarySelectedEntries.map(\.path)
                                : browser.selectedEntries.map(\.path)
                            marqueeStart = value.startLocation
                            marqueeCurrent = value.location
                            folderDragStarted = false
                            return
                        }
                    }

                    // Arrastre sobre fila no seleccionada o vacío: inicia selección marquesina (como Finder)
                    marqueeStart = value.startLocation
                    marqueeCurrent = value.location
                    folderDragPaths = []
                    marqueeCommitted = false
                    marqueeStartEntryID = entryAtY(value.startLocation.y)?.id
                    marqueeAdditive = flags.contains(.shift)
                    marqueeBase = marqueeAdditive
                        ? (isSecondary ? browser.secondarySelectedIDs : browser.selectedIDs)
                        : []
                    // No limpiar selección hasta confirmar marquee (si no, un temblor deja multi raro).
                }

                if !folderDragPaths.isEmpty {
                    let dist = hypot(value.translation.width, value.translation.height)
                    if !folderDragStarted, dist >= PressDragSelectLogic.moveThreshold {
                        folderDragStarted = true
                        _ = browser.startDragWithPaths(folderDragPaths)
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
                if folderDragPaths.isEmpty {
                    if marqueeCommitted {
                        applyMarquee()
                    }
                    // Si no hubo marquee committed (clic limpio o micro-movimiento),
                    // FileRowButton ya gestiona el clic directamente sin pisar ⌘ ni ⇧.
                }
                resetMarquee()
            }
    }

    private func applyMarquee() {
        guard let start = marqueeStart, let current = marqueeCurrent else { return }
        let entries = paneEntries
        guard !entries.isEmpty else { return }

        let y0 = min(start.y, current.y)
        let y1 = max(start.y, current.y)
        let contentH = listContentHeight

        // Rectángulo solo en el vacío debajo de los archivos → nada
        if y0 >= contentH {
            if isSecondary {
                browser.applySecondaryMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            } else {
                browser.applyMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            }
            return
        }

        let first = max(0, Int(floor(y0 / rowHeight)))
        let last = min(entries.count - 1, Int(floor((min(y1, contentH) - 0.001) / rowHeight)))
        guard first <= last else {
            if isSecondary {
                browser.applySecondaryMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            } else {
                browser.applyMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            }
            return
        }
        let hits = Set(entries[first...last].map(\.id))
        if isSecondary {
            browser.applySecondaryMarqueeSelection(hitIDs: hits, base: marqueeBase, additive: marqueeAdditive)
        } else {
            browser.applyMarqueeSelection(hitIDs: hits, base: marqueeBase, additive: marqueeAdditive)
        }
    }

    private var header: some View {
        HStack(spacing: metrics.isCompact ? 8 : 12) {
            Button {
                if isSecondary {
                    browser.toggleSelectAllSecondary()
                } else {
                    browser.toggleSelectAllVisible()
                }
            } label: {
                Image(systemName: paneAllSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help(L10n.s("Seleccionar / quitar todos", "Select / deselect all"))

            Text(L10n.s("Nombre / ruta", "Name / Path"))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !metrics.isCompact {
                Text(L10n.s("Tipo", "Type"))
                    .frame(width: 100, alignment: .leading)
            }
            // Siempre visible: al filtrar ordenamos por esto (más nuevo arriba).
            Text(L10n.s("Agregado", "Date Added"))
                .frame(width: metrics.isCompact ? 108 : 130, alignment: .trailing)
            Text(L10n.s("Tamaño", "Size"))
                .frame(width: metrics.isCompact ? 72 : 84, alignment: .trailing)
            Color.clear.frame(width: 28)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, metrics.contentPadding)
        .padding(.vertical, metrics.isCompact ? 6 : 8)
    }
}

struct FileRowButton: View {
    @EnvironmentObject private var browser: BrowserModel
    @Environment(\.ordenMetrics) private var metrics
    let entry: FileEntry
    let zebra: Bool
    var pane: BrowserModel.PaneFocus = .primary

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
        HStack(alignment: .center, spacing: 8) {
            Button {
                if isSecondary {
                    browser.toggleSecondarySelection(entry.id)
                } else {
                    browser.toggleSelection(entry.id)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(isSelected ? OrdenTheme.accent : .secondary)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.s("Marcar / desmarcar", "Select / deselect"))
            .padding(.leading, 10)

            // Clic/doble clic en la fila (no Button): evita pelear con TapGesture y con el monitor AppKit.
            HStack(alignment: .center, spacing: metrics.isCompact ? 8 : 12) {
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
                .frame(maxWidth: .infinity, alignment: .leading)

                if !metrics.isCompact {
                    Text(entry.category.labelLocalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                }
                Text(entry.dateAdded, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.isCompact ? 108 : 130, alignment: .trailing)
                Text(sizeLabel)
                    .font(.caption.monospacedDigit().weight(entry.size > 100_000_000 ? .semibold : .regular))
                    .foregroundStyle(entry.size > 500_000_000 ? .orange : .secondary)
                    .frame(width: metrics.isCompact ? 72 : 84, alignment: .trailing)
            }
            .padding(.vertical, metrics.isCompact ? 10 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    ensureSelectedAlone()
                    if isSecondary {
                        browser.openSecondaryEntry(entry)
                    } else {
                        browser.activateEntry(entry)
                    }
                }
            )
            .onTapGesture(count: 1) {
                selectRow()
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
        .opacity(isCut ? 0.42 : 1)
        .background(rowBackground)
        .fileDragArmHighlight(path: entry.path)
        .reportFileDragArmFrame(path: entry.path)
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
                browser.quickLookSelection()
            }
            Button(L10n.s("Mostrar en Finder", "Show in Finder")) { browser.revealInFinder(entry) }
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

    private func selectRow() {
        browser.isAssistantFocused = false
        if FindaroTextInput.isEditing {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
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

                Button(action: browser.goForward) {
                    Label(L10n.s("Adelante", "Forward"), systemImage: "chevron.forward")
                }
                .disabled(!browser.canGoForward)
                .help(L10n.s("Carpeta siguiente (⌘2 o ⌥→)", "Next folder (⌘2 or ⌥→)"))

                Button(action: browser.goUp) {
                    Label(L10n.s("Arriba", "Enclosing Folder"), systemImage: "chevron.up")
                }
                .help(L10n.s("Carpeta superior (⌘↑)", "Enclosing folder (⌘↑)"))

                Button {
                    session.addTab()
                } label: {
                    Label(L10n.s("Nueva pestaña", "New Tab"), systemImage: "plus.square.on.square")
                }
                .help(L10n.s("Nueva pestaña (⌘T)", "New tab (⌘T)"))

                Button {
                    openWindow(id: "browser")
                } label: {
                    Label(L10n.s("Nueva ventana", "New Window"), systemImage: "macwindow.badge.plus")
                }
                .help(L10n.s("Nueva ventana (⌘⌥N)", "New window (⌘⌥N)"))
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    ViewModePicker()
                    PathBreadcrumbBar()
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    browser.promptNewFolder()
                } label: {
                    Label(L10n.s("Nueva carpeta", "New Folder"), systemImage: "folder.badge.plus")
                }
                .help(L10n.s("Nueva carpeta en este sitio (⇧⌘N)", "New folder here (⇧⌘N)"))

                Button {
                    browser.promptNewFile()
                } label: {
                    Label(L10n.s("Nuevo archivo", "New File"), systemImage: "doc.badge.plus")
                }
                .help(L10n.s("Nuevo archivo vacío (⌘N)", "New empty file (⌘N)"))

                ToolbarStateToggle(
                    isOn: $browser.showAssistantPanel,
                    title: L10n.s("Asistente", "Assistant"),
                    onSymbol: "sparkles",
                    offSymbol: "sparkles",
                    helpOn: L10n.s("Asistente ON · clic para cerrar (⌘5)", "Assistant ON · click to close (⌘5)"),
                    helpOff: L10n.s("Asistente OFF · abrir (⌘5)", "Assistant OFF · open (⌘5)")
                )

                ToolbarStateToggle(
                    isOn: $browser.multiSelectMode,
                    title: L10n.s("Varios", "Multi-Select"),
                    onSymbol: "checkmark.circle.fill",
                    offSymbol: "checkmark.circle",
                    helpOn: L10n.s("Modo varios ON · cada clic suma/quita", "Multi-select ON · each click adds/removes"),
                    helpOff: L10n.s("Modo varios OFF · clic normal", "Multi-select OFF · normal click")
                )

                Button {
                    browser.selectAllVisible()
                } label: {
                    Label(L10n.s("Todos", "All"), systemImage: "checklist")
                }
                .help(L10n.s("Seleccionar todo lo visible (⌘A)", "Select all visible (⌘A)"))

                Button {
                    browser.cancelSelection()
                } label: {
                    Label(L10n.s("Ninguno", "None"), systemImage: "xmark.circle")
                }
                .help(L10n.s("Quitar selección (Esc)", "Clear selection (Esc)"))
                .disabled(browser.selectedIDs.isEmpty)

                Button {
                    browser.openSelection()
                } label: {
                    Label(L10n.s("Abrir", "Open"), systemImage: "arrow.up.forward.app")
                }
                .help(L10n.s("Abrir lo seleccionado (⌘↓)", "Open selection (⌘↓)"))
                .disabled(browser.selectedIDs.isEmpty)

                Button {
                    browser.quickLookSelection()
                } label: {
                    Label(L10n.s("Vista rápida", "Quick Look"), systemImage: "eye")
                }
                .help(L10n.s("Vista rápida (Espacio)", "Quick Look (Space)"))
                .disabled(browser.selectedIDs.isEmpty)

                ToolbarStateToggle(
                    isOn: Binding(
                        get: { browser.showRowPaths },
                        set: { browser.setShowRowPaths($0) }
                    ),
                    title: L10n.s("Rutas", "Paths"),
                    onSymbol: "list.bullet.rectangle.fill",
                    offSymbol: "list.bullet",
                    helpOn: L10n.s("Rutas bajo el nombre ON", "Paths under name ON"),
                    helpOff: L10n.s("Rutas bajo el nombre OFF", "Paths under name OFF")
                )

                ToolbarStateToggle(
                    isOn: Binding(
                        get: { browser.showHiddenFiles },
                        set: { browser.setShowHiddenFiles($0) }
                    ),
                    title: L10n.s("Ocultos", "Hidden"),
                    onSymbol: "eye.fill",
                    offSymbol: "eye.slash",
                    helpOn: L10n.s("Ocultos visibles ON · ⌘⇧.", "Hidden files visible ON · ⌘⇧."),
                    helpOff: L10n.s("Ocultos escondidos · ⌘⇧.", "Hidden files concealed · ⌘⇧.")
                )

                Button {
                    browser.openTerminalHere()
                } label: {
                    Label(L10n.s("Terminal", "Terminal"), systemImage: "terminal")
                }
                .help(L10n.s("Abrir Terminal en la carpeta activa (⌘⌥T)", "Open Terminal in active folder (⌘⌥T)"))

                Button {
                    browser.reloadFromUser()
                } label: {
                    Label(L10n.s("Actualizar", "Refresh"), systemImage: "arrow.clockwise")
                }
                .help(L10n.s("Actualizar esta carpeta y avisarte en el asistente", "Refresh current folder and notify assistant"))
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
            }
            .sheet(isPresented: $browser.showNewFileDialog) {
                NamePromptSheet(kind: .newFile)
                    .environmentObject(browser)
            }
            .sheet(isPresented: $browser.showRenameDialog) {
                NamePromptSheet(kind: .rename)
                    .environmentObject(browser)
            }
            .sheet(isPresented: $browser.showGoToFolderDialog) {
                GoToFolderSheet()
                    .environmentObject(browser)
            }
            .sheet(isPresented: $browser.showDeepSearchDialog) {
                DeepSearchSheet()
                    .environmentObject(browser)
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
            .sheet(item: $browser.pendingMergePreview) { preview in
                MergePreviewSheet(preview: preview)
                    .environmentObject(browser)
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
                    Picker("", selection: Binding(
                        get: { browser.appLanguage },
                        set: { browser.setAppLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .frame(width: 180)
                }

                settingsRow(
                    icon: "keyboard",
                    tint: OrdenTheme.accent,
                    title: L10n.s("Atajo global", "Global Hotkey"),
                    subtitle: L10n.s("Abre Findaro en «\(browser.globalHotkeyFolderDisplayName)»", "Opens Findaro in «\(browser.globalHotkeyFolderDisplayName)»")
                ) {
                    HStack(spacing: 6) {
                        let globalChord = browser.chord(forHotkey: "nav.globalOpen")
                            ?? KeyChord(keyCode: 31, character: "o", option: true, control: true)
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
            ForEach(AppHotkeyGroup.allCases, id: \.self) { group in
                let items = AppHotkeyCatalog.catalog.filter { $0.group == group }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { def in
                            keyboardHotkeyRow(def)
                        }
                    } header: {
                        if group == AppHotkeyGroup.allCases.first {
                            HStack {
                                Text(group.titleLocalized)
                                Spacer()
                                Button(L10n.s("Restaurar teclado", "Restore Shortcuts")) {
                                    browser.restoreDefaultKeyboardHotkeys()
                                }
                                .font(.caption)
                            }
                        } else {
                            Text(group.titleLocalized)
                        }
                    } footer: {
                        if group == .view {
                            Text(L10n.s("Clic para cambiar la tecla. Reinicia Findaro si el menú de macOS no se actualiza.", "Click to change shortcut key. Relaunch Findaro if the macOS menu does not refresh immediately."))
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
                            Text(tier == "family" ? L10n.s("Familiar (hasta 5 Macs)", "Family (up to 5 Macs)") : L10n.s("Personal (hasta 2 Macs)", "Personal (up to 2 Macs)"))
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text(L10n.s("Equipos activos:", "Active devices:"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(L10n.s("\(activeCount) de \(seats) Macs registradas", "\(activeCount) of \(seats) Macs registered"))
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
                                Label(L10n.s("Comprar licencia ($39 USD · 2 Macs)", "Buy License ($39 USD · 2 Macs)"), systemImage: "cart.fill")
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
                                Text(L10n.s("Prueba de 5 días finalizada", "5-day trial expired"))
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
                                Label(L10n.s("Comprar licencia de por vida ($39 USD)", "Buy lifetime license ($39 USD)"), systemImage: "cart.fill")
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
                            TextField("FINDARO-XXXX-XXXX-XXXX-XXXX", text: $licenseInput)
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
                    Text(L10n.s("• Plan Personal: incluye 2 Macs por $39 USD (pago único de por vida).", "• Personal Plan: includes 2 Macs for $39 USD (one-time lifetime payment)."))
                    Text(L10n.s("• Plan Familiar: incluye 5 Macs por $59 USD.", "• Family Plan: includes 5 Macs for $59 USD."))
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

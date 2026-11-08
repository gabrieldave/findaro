import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

struct ContentView: View {
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
            // Omnibox / sheets: no abrir ni renombrar detrás.
            if browser.pathOmniboxEditing {
                browser.submitPathOmnibox()
                return .handled
            }
            if browser.hasModalSheet { return .ignored }
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
                    Text("Suelta para meter en «\(URL(fileURLWithPath: dest).lastPathComponent)»")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text("⌥ copia · ⌘Z deshace")
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
                                    Text("Origen")
                                        .font(.system(size: 12, weight: .semibold))
                                    if browser.focusedPane == .primary {
                                        FindaroStatusPill(title: "activo", kind: .processing)
                                    }
                                    Spacer(minLength: 4)
                                    if browser.focusedPane != .primary {
                                        Button {
                                            browser.focusOriginPane()
                                        } label: {
                                            Label("Activar", systemImage: "arrow.left.circle.fill")
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(OrdenTheme.accent)
                                        .controlSize(.small)
                                        .help("Enfoca el panel izquierdo · Tab · ⌘⇧← · o clic en vacío")
                                    }
                                    Button {
                                        browser.swapPaneFolders()
                                    } label: {
                                        Image(systemName: "arrow.left.arrow.right")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Intercambiar carpetas Origen ↔ Destino")
                                    Button {
                                        browser.goUp()
                                    } label: {
                                        Image(systemName: "arrow.up.left")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Subir en el panel izquierdo")
                                    // Solo acciones hacia Destino (→). «← Mover / ← Copiar» viven en Destino.
                                    Button {
                                        browser.transferPrimarySelectionToSecondary(copy: false)
                                    } label: {
                                        Label("Mover →", systemImage: "arrow.right.circle.fill")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .controlSize(.small)
                                    .help("Mueve lo seleccionado aquí → Destino · ⌘⇧M")
                                    Button {
                                        browser.transferPrimarySelectionToSecondary(copy: true)
                                    } label: {
                                        Text("Copiar →")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .controlSize(.small)
                                    .help("Copia lo seleccionado aquí → Destino")
                                }
                                // Tap en ruta/ayuda enfoca Origen; no envolver botones (bloqueaba Mover/Copiar).
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(shortPath(browser.currentPath))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(browser.currentPath)
                                    Text("Misma lista · naranja · Arrastra ↔ · Swap intercambia carpetas")
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
                        Text(browser.transferProgressLabel ?? "Transferiendo…")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        FindaroStatusPill(title: "En curso", kind: .processing)
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
                Button("Todos · \(browser.entries.count)") {
                    browser.clearCategoryFilter()
                }
                if !browser.categoryCounts.isEmpty {
                    Divider()
                    ForEach(browser.categoryCounts, id: \.category) { row in
                        Button("\(row.category.labelSpanish) · \(row.count)") {
                            browser.categoryFilter = row.category
                        }
                    }
                }
            } label: {
                Label(browser.categoryFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderedButton)
            .tint(browser.categoryFilter == nil ? nil : OrdenTheme.accent)
            .help("Filtra por tipo: imágenes, vídeos, zips…")

            Button {
                browser.toggleDownloadsTodayMode()
            } label: {
                Label(
                    browser.downloadsTodayMode ? "Salir descargados" : "Descargados",
                    systemImage: browser.downloadsTodayMode ? "xmark.circle" : "arrow.down.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(browser.downloadsTodayMode ? .orange : OrdenTheme.accent)
            .controlSize(.regular)
            .help("Solo lo bajado o agregado hoy en esta carpeta (oculta el resto)")

            if browser.cleanupMode {
                Button {
                    browser.exitCleanupMode()
                } label: {
                    Label("Volver al orden normal", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.regular)
                .help("Quita el orden por peso y regresa al orden que tenías")
            } else if !browser.downloadsTodayMode {
                Button {
                    browser.showHeaviestForCleanup()
                } label: {
                    Label("Más pesados", systemImage: "gauge.with.dots.needle.67percent")
                }
                .help("No borra nada: solo pone arriba lo que más ocupa espacio")
                .controlSize(.regular)
            }

            if !browser.downloadsTodayMode {
                Button {
                    browser.useDownloadsStyleEverywhere()
                } label: {
                    Label("En todas partes", systemImage: "globe")
                }
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
                        ? "Buscando…"
                        : (browser.showDeepSearchPanel ? "Salir búsqueda" : "Subcarpetas"),
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
                    ? "Cerrar búsqueda y volver al orden normal · Esc"
                    : "Por nombre, desde esta carpeta hacia abajo · ⌘4"
            )

            if !browser.downloadsTodayMode {
                Menu {
                    Section("Cambiar orden (se guarda)") {
                        sortButtons(scope: .everywhere)
                    }
                    Divider()
                    Section("Solo esta carpeta") {
                        sortButtons(scope: .thisFolder)
                    }
                    if browser.hasFolderOverride {
                        Button("Quitar orden propio (usar global)") {
                            browser.useGlobalDefaultHere()
                        }
                    }
                } label: {
                    Label("Ordenar", systemImage: "line.3.horizontal.decrease")
                }
                .menuStyle(.borderedButton)

                Menu {
                    if browser.viewTemplates.isEmpty {
                        Text("Sin plantillas todavía")
                    } else {
                        Section("Aplicar plantilla") {
                            ForEach(browser.viewTemplates) { template in
                                Button {
                                    browser.applyViewTemplate(template)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name)
                                        Text(template.summarySpanish)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Guardar vista actual como plantilla…") {
                        browser.promptSaveViewTemplate()
                    }
                    if !browser.viewTemplates.isEmpty {
                        Menu("Eliminar plantilla") {
                            ForEach(browser.viewTemplates) { template in
                                Button(role: .destructive) {
                                    browser.deleteViewTemplate(template)
                                } label: {
                                    Text(template.name)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Plantillas", systemImage: "rectangle.stack")
                }
                .menuStyle(.borderedButton)
                .help(Self.plantillasHelp)

                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(Self.plantillasHelp)
                    .accessibilityLabel("Qué son las plantillas")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static let plantillasHelp = """
    Plantillas = formas guardadas de ver tus archivos.

    Ejemplo: ordenas por «Más pesados», eliges lista o iconos, y lo guardas como plantilla «Pesados». Después la vuelves a aplicar con un clic, o dejas esa vista puesta.

    También puedes combinar (tipo + orden) y guardar tu propia mezcla. El menú Ordenar cambia el orden al momento; Plantillas guarda y recarga esas combinaciones.
    """

    @ViewBuilder
    private func sortButtons(scope: SortSaveScope) -> some View {
        Button("Estilo Descargas (tipos · Agregado ↓)") {
            browser.applyRule(.downloads, scope: scope)
        }
        Button("Solo Agregado · lo más nuevo arriba") {
            browser.applyRule(.newestAddedFirst, scope: scope)
        }
        Button("Nombre A→Z") {
            browser.applyRule(
                SortRule(keys: [.name(ascending: true)], foldersFirst: true),
                scope: scope
            )
        }
        Button("Por tipo fijo") {
            browser.applyRule(.byType, scope: scope)
        }
        Button("Más pesados primero") {
            browser.applyRule(.heaviestFirst, scope: scope)
        }
        Toggle(
            "Carpetas arriba",
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
                Label("Quitar filtro", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.regular)
            .help("Quita búsqueda, tipo, descargados y atajos · Esc. Al filtrar la lista va por Agregado (más nuevo arriba).")
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
            parts.append("búsqueda subcarpetas")
        }
        if !browser.searchText.isEmpty {
            parts.append("filtro «\(browser.searchText)»")
        }
        if browser.categoryFilter != nil {
            parts.append("tipo")
        }
        if browser.downloadsTodayMode {
            parts.append("descargados hoy")
        }
        if browser.cleanupMode {
            parts.append("más pesados")
        }
        if browser.activeAssistantShortcut != nil {
            parts.append("atajo")
        }
        if parts.isEmpty { return "Filtros activos · más nuevo arriba" }
        return "Activo: " + parts.joined(separator: " · ") + " · más nuevo arriba"
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
                            .help("Ir a \(segment.path)")
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
                .help("Copiar ruta completa")
                Label(browser.folderTotalLabel, systemImage: "externaldrive.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                if browser.isMeasuringSizes {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(
                    browser.downloadsTodayMode
                        ? "· \(browser.visibleEntries.count) de hoy / \(browser.entries.count)"
                        : "· \(browser.entries.count) elementos"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let shortcut = browser.activeAssistantShortcut {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                    Text("Atajo «\(shortcut.title)»: \(browser.visibleEntries.count) coincidencias. El resto está oculto.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Mostrar todo") {
                        browser.clearAssistantShortcutFilter()
                    }
                    .controlSize(.regular)
                }
            } else if browser.downloadsTodayMode {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Solo descargas / archivos de hoy en esta carpeta. El resto está oculto.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Mostrar todo") {
                        browser.exitDownloadsTodayMode()
                    }
                    .controlSize(.small)
                }
            }

            // Solo con orden por peso — evita una segunda franja permanente
            if browser.cleanupMode {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ordenado por peso (no se borra nada). Toca uno para seleccionarlo:")
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

                sectionHeader("Ubicaciones")
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
            SidebarItem(
                id: "fav-\(path)",
                title: URL(fileURLWithPath: path).lastPathComponent,
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

        let trash = (home as NSString).appendingPathComponent(".Trash")
        return SidebarLocations.make(
            homePath: home,
            iCloudPath: fm.fileExists(atPath: iCloud) ? iCloud : nil,
            cloudFolders: clouds,
            volumes: volumes,
            trashPath: fm.fileExists(atPath: trash) ? trash : nil
        ).map {
            SidebarItem(id: $0.id, title: $0.title, path: $0.path, systemImage: $0.systemImage)
        }
    }

    private var favoritesDropZone: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("FAVORITOS")
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
                .help("Añadir la carpeta actual a Favoritos")
                Button {
                    browser.pickFolderAsFavorite()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.body)
                        .foregroundStyle(OrdenTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Elegir otra carpeta…")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(favoriteItems) { item in
                sidebarButton(item, isFavoriteSlot: true)
            }

            Text(favoritesDropTargeted ? "Suelta para fijar" : "Usa «A Favoritos» o suelta desde Finder")
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
                Button("Quitar de Favoritos", role: .destructive) {
                    browser.removeFavorite(item.path)
                }
            } else {
                Button("Añadir a Favoritos") {
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
                ContentUnavailableView(
                    "No se pudo abrir",
                    systemImage: "exclamationmark.folder",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if paneEntries.isEmpty && (isSecondary || browser.viewMode != .columns) {
                ContentUnavailableView(
                    "Vacío",
                    systemImage: "folder",
                    description: Text(isSecondary
                        ? "Suelta archivos aquí o usa «Mover →»"
                        : "No hay elementos con este filtro.")
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
                        _ = browser.startArmedNativeDrag()
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
                    } else if let id = marqueeStartEntryID {
                        // Arrastre corto / temblor: 1 solo ítem (el del clic).
                        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                        if isSecondary {
                            if flags.contains(.shift) {
                                browser.selectSecondaryRange(to: id)
                            } else if browser.multiSelectMode {
                                browser.toggleSecondarySelection(id)
                            } else {
                                browser.selectSecondaryOnly(id)
                            }
                        } else if flags.contains(.shift) {
                            browser.selectRange(to: id)
                        } else if browser.multiSelectMode {
                            browser.toggleSelection(id)
                        } else {
                            browser.selectOnly(id)
                        }
                    }
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
            .help("Seleccionar / quitar todos")

            Text("Nombre / ruta")
                .frame(maxWidth: .infinity, alignment: .leading)
            if !metrics.isCompact {
                Text("Tipo")
                    .frame(width: 100, alignment: .leading)
            }
            // Siempre visible: al filtrar ordenamos por esto (más nuevo arriba).
            Text("Agregado")
                .frame(width: metrics.isCompact ? 108 : 130, alignment: .trailing)
            Text("Tamaño")
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
            .help("Marcar / desmarcar")
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
                    Text(entry.category.labelSpanish)
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
            .onTapGesture(count: 2) {
                ensureSelectedAlone()
                if isSecondary {
                    browser.openSecondaryEntry(entry)
                } else {
                    browser.activateEntry(entry)
                }
            }
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
            .help("Copiar ruta completa")
            .padding(.trailing, 10)
        }
        .opacity(isCut ? 0.42 : 1)
        .background(rowBackground)
        .fileDragArmHighlight(path: entry.path)
        .reportFileDragArmFrame(path: entry.path)
        .folderDropTarget(entry: entry)
        .fileDragArmPress(entry: entry, browser: browser)
        .contextMenu {
            Button("Abrir") {
                ensureSelectedAlone()
                if isSecondary {
                    browser.openSecondaryEntry(entry)
                } else {
                    browser.open(entry)
                }
            }
            OpenWithMenu(entry: entry)
            Button("Obtener información") {
                ensureSelectedAlone()
                browser.showInfo(entry)
            }
            if entry.isDirectory {
                if browser.isFavorite(entry.path) {
                    Button("Quitar de Favoritos") {
                        browser.removeFavorite(entry.path)
                    }
                } else {
                    Button("Añadir a Favoritos") {
                        browser.addFavorite(entry.path)
                    }
                }
            }
            Button("Renombrar") {
                ensureSelectedAlone()
                browser.promptRename()
            }
            Button("Duplicar") {
                ensureInSelection()
                browser.duplicateSelection()
            }
            Button("Comprimir") {
                ensureInSelection()
                browser.compressSelection()
            }
            if ArchiveOps.isExtractable(entry.path) {
                Button("Descomprimir aquí") {
                    ensureSelectedAlone()
                    browser.extractArchive(entry, intoSecondary: isSecondary)
                }
            }
            Button("A bandeja") {
                ensureInSelection()
                browser.addSelectionToShelf()
            }
            Button("Vista rápida") {
                ensureSelectedAlone()
                browser.quickLookSelection()
            }
            Button("Mostrar en Finder") { browser.revealInFinder(entry) }
            Button("Copiar") {
                ensureInSelection()
                browser.copySelectionToPasteboard()
            }
            Button("Copiar ruta completa") { browser.copyPath(entry) }
            if browser.dualPaneEnabled {
                Divider()
                if isSecondary {
                    Button("Mover a Origen") {
                        ensureInSelection()
                        browser.transferSecondarySelectionToPrimary(copy: false)
                    }
                    Button("Copiar a Origen") {
                        ensureInSelection()
                        browser.transferSecondarySelectionToPrimary(copy: true)
                    }
                } else {
                    Button("Mover a Destino") {
                        ensureInSelection()
                        browser.transferPrimarySelectionToSecondary(copy: false)
                    }
                    Button("Copiar a Destino") {
                        ensureInSelection()
                        browser.transferPrimarySelectionToSecondary(copy: true)
                    }
                }
            }
            Divider()
            Button("Nueva carpeta aquí") {
                browser.focusPane(pane)
                browser.promptNewFolder()
            }
            Button("Nuevo archivo aquí") {
                browser.focusPane(pane)
                browser.promptNewFile()
            }
            Button("Seleccionar todos") {
                if isSecondary {
                    browser.selectAllSecondaryVisible()
                } else {
                    browser.selectAllVisible()
                }
            }
            Button("Quitar selección") {
                if isSecondary {
                    browser.clearSecondarySelection()
                } else {
                    browser.clearSelection()
                }
            }
            Divider()
            Button("Mover a la Papelera", role: .destructive) {
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

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: browser.goBack) {
                    Label("Atrás", systemImage: "chevron.backward")
                }
                .disabled(!browser.canGoBack)
                .help("Carpeta anterior (⌘1 o ⌥←)")

                Button(action: browser.goForward) {
                    Label("Adelante", systemImage: "chevron.forward")
                }
                .disabled(!browser.canGoForward)
                .help("Carpeta siguiente (⌘2 o ⌥→)")

                Button(action: browser.goUp) {
                    Label("Arriba", systemImage: "chevron.up")
                }
                .help("Carpeta superior (⌘↑)")
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
                    Label("Nueva carpeta", systemImage: "folder.badge.plus")
                }
                .help("Nueva carpeta en este sitio (⇧⌘N)")

                Button {
                    browser.promptNewFile()
                } label: {
                    Label("Nuevo archivo", systemImage: "doc.badge.plus")
                }
                .help("Nuevo archivo vacío (⌘N)")

                ToolbarStateToggle(
                    isOn: $browser.showAssistantPanel,
                    title: "Asistente",
                    onSymbol: "sparkles",
                    offSymbol: "sparkles",
                    helpOn: "Asistente ON · clic para cerrar (⌘5)",
                    helpOff: "Asistente OFF · abrir (⌘5)"
                )

                ToolbarStateToggle(
                    isOn: $browser.multiSelectMode,
                    title: "Varios",
                    onSymbol: "checkmark.circle.fill",
                    offSymbol: "checkmark.circle",
                    helpOn: "Modo varios ON · cada clic suma/quita",
                    helpOff: "Modo varios OFF · clic normal"
                )

                Button {
                    browser.selectAllVisible()
                } label: {
                    Label("Todos", systemImage: "checklist")
                }
                .help("Seleccionar todo lo visible (⌘A)")

                Button {
                    browser.cancelSelection()
                } label: {
                    Label("Ninguno", systemImage: "xmark.circle")
                }
                .help("Quitar selección (Esc)")
                .disabled(browser.selectedIDs.isEmpty)

                Button {
                    browser.openSelection()
                } label: {
                    Label("Abrir", systemImage: "arrow.up.forward.app")
                }
                .help("Abrir lo seleccionado (⌘↓)")
                .disabled(browser.selectedIDs.isEmpty)

                Button {
                    browser.quickLookSelection()
                } label: {
                    Label("Vista rápida", systemImage: "eye")
                }
                .help("Vista rápida (Espacio)")
                .disabled(browser.selectedIDs.isEmpty)

                ToolbarStateToggle(
                    isOn: Binding(
                        get: { browser.showRowPaths },
                        set: { browser.setShowRowPaths($0) }
                    ),
                    title: browser.showRowPaths ? "Rutas" : "Rutas",
                    onSymbol: "list.bullet.rectangle.fill",
                    offSymbol: "list.bullet",
                    helpOn: "Rutas bajo el nombre ON",
                    helpOff: "Rutas bajo el nombre OFF"
                )

                ToolbarStateToggle(
                    isOn: Binding(
                        get: { browser.showHiddenFiles },
                        set: { browser.setShowHiddenFiles($0) }
                    ),
                    title: "Ocultos",
                    onSymbol: "eye.fill",
                    offSymbol: "eye.slash",
                    helpOn: "Ocultos visibles ON · ⌘⇧.",
                    helpOff: "Ocultos escondidos · ⌘⇧."
                )

                Button {
                    browser.openTerminalHere()
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
                .help("Abrir Terminal en la carpeta activa (⌘⌥T)")

                Button {
                    browser.reloadFromUser()
                } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
                .help("Actualizar esta carpeta y avisarte en el asistente")
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
    @State private var editingShortcut: AssistantShortcut?
    @State private var showNewShortcut = false
    @State private var editingHotkey: AppHotkeyDefinition?

    var body: some View {
        TabView {
            settingsGeneral
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            settingsAssistant
                .tabItem { Label("Asistente", systemImage: "sparkles") }
            settingsShortcuts
                .tabItem { Label("Atajos", systemImage: "keyboard") }
            settingsSearch
                .tabItem { Label("Búsqueda", systemImage: "magnifyingglass") }
            settingsMaintenance
                .tabItem { Label("Mantenimiento", systemImage: "wrench.and.screwdriver") }
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
                    icon: "keyboard",
                    tint: OrdenTheme.accent,
                    title: "Atajo global",
                    subtitle: "Abre Findaro en «\(browser.globalHotkeyFolderDisplayName)»"
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
                        .help("Cambiar teclas del atajo global")

                        Button {
                            browser.pickGlobalHotkeyFolder()
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.title3)
                                .foregroundStyle(OrdenTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Elegir carpeta que abre el atajo")

                        if browser.usesCustomGlobalHotkeyFolder {
                            Button {
                                browser.resetGlobalHotkeyFolder()
                            } label: {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Volver a Descargas")
                        }
                    }
                }

                settingsRow(
                    icon: "folder.badge.gearshape",
                    tint: .orange,
                    title: "Abrir carpetas con Findaro",
                    subtitle: OpenFolderBridge.isDefaultFolderHandler()
                        ? "Findaro es la app por defecto"
                        : "macOS obliga un paso manual (Abrir con → Siempre)"
                ) {
                    Button(OpenFolderBridge.isDefaultFolderHandler() ? "Ver cómo" : "Preparar…") {
                        browser.runFolderHandlerSetup()
                    }
                }
            } header: {
                Text("Inicio rápido")
            } footer: {
                Text("Lapicito = cambiar teclas · carpeta = a dónde abre. «Abrir con → Siempre» es aparte.")
            }

            Section {
                settingsRow(
                    icon: "arrow.up.arrow.down",
                    tint: OrdenTheme.accent,
                    title: "Orden de esta sesión",
                    subtitle: browser.rule.summarySpanish
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
                        Text("Teclado tipo Explorer")
                        Text("Enter abre · F2 renombra (si no, Enter renombra como Finder)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { browser.showHiddenFiles },
                    set: { browser.setShowHiddenFiles($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mostrar ocultos")
                        Text("Archivos con punto o flag hidden · ⌘⇧.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { browser.flattenFolderView },
                    set: { browser.setFlattenFolderView($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vista plana")
                        Text("Lista archivos de subcarpetas sin jerarquía")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Lista de archivos")
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
                        Text("Inteligencia local")
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
                    Label("Configurar / detectar Ollama…", systemImage: "waveform.badge.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(OrdenTheme.accent)
                .controlSize(.large)
            } header: {
                Text("Ollama (opcional)")
            } footer: {
                Text("Si no quieres IA, no pasa nada: el asistente sigue con atajos y reglas. Nada se sube a internet.")
            }

            Section {
                tipLine(
                    icon: "mic.circle.fill",
                    title: "Voz (mantener micrófono)",
                    detail: "En el asistente: mantén, habla en español, suelta. Local en tu Mac."
                )
                Button("Abrir asistente (⌘5)") {
                    browser.showAssistantPanel = true
                }
                Text("Los atajos se editan en la pestaña Atajos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Panel y voz")
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
                                Text(group.titleSpanish)
                                Spacer()
                                Button("Restaurar teclado") {
                                    browser.restoreDefaultKeyboardHotkeys()
                                }
                                .font(.caption)
                            }
                        } else {
                            Text(group.titleSpanish)
                        }
                    } footer: {
                        if group == .view {
                            Text("Clic para cambiar la tecla. Reinicia Findaro si el menú de macOS no se actualiza.")
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
                    Label("Nuevo filtro", systemImage: "plus")
                }
                .disabled(browser.assistantShortcuts.count >= AssistantShortcut.maxCount)
            } header: {
                HStack {
                    Text("Filtros del asistente")
                    Spacer()
                    Text("\(browser.assistantShortcuts.count)/\(AssistantShortcut.maxCount)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                HStack {
                    Button("Restaurar filtros") {
                        browser.restoreDefaultAssistantShortcuts()
                    }
                    Spacer()
                    Text("Imágenes de hoy, docs de ayer…")
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
                    Text(def.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(def.detail)
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
                Button("Cambiar…") { editingHotkey = def }
                Button("Restablecer") { browser.resetKeyboardHotkey(def.id) }
                    .disabled(!customized)
            }
        }
        .help(def.isEditable ? "Clic para cambiar" : "Atajo del sistema (no editable aquí)")
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
                    Text(shortcut.title)
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
            Button("Editar") { editingShortcut = shortcut }
            Button("Usar ahora") {
                browser.showAssistantPanel = true
                browser.applyAssistantShortcut(shortcut)
            }
            Divider()
            Button("Borrar", role: .destructive) {
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
            type = "Documentos"
        } else if shortcut.categories.isEmpty {
            type = "Cualquier tipo"
        } else if shortcut.categories.count == 1, let only = shortcut.categories.first {
            type = only.labelSpanish
        } else {
            type = "\(shortcut.categories.count) tipos"
        }
        return "\(type) · \(shortcut.dateWindow.labelSpanish)"
    }

    // MARK: Búsqueda

    private var settingsSearch: some View {
        Form {
            Section {
                tipLine(icon: "doc.text.magnifyingglass", title: "Filtro de arriba", detail: "Solo nombres en esta carpeta")
                tipLine(icon: "magnifyingglass.circle.fill", title: "Subcarpetas · ⌘4", detail: "Esta carpeta y todo lo de adentro")
                tipLine(icon: "checkmark.circle.fill", title: "Coincide por parte del nombre", detail: "vibe encuentra vibesystems…")
                tipLine(icon: "xmark.circle.fill", title: "No lee el contenido", detail: "Eso es del asistente / Ollama")
            } header: {
                Text("Cómo busca Findaro")
            } footer: {
                Text("Sin comodines (* ?) y sin Spotlight. El asistente (⌘5) es aparte.")
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
                    title: "Versión",
                    subtitle: "ordena.iareal.net"
                ) {
                    Text(AppUpdateChecker.currentVersion())
                        .font(.body.monospaced().weight(.semibold))
                }
                Button {
                    Task { await AppUpdateChecker.shared.check(interactive: true) }
                } label: {
                    Label("Buscar actualizaciones…", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } header: {
                Text("Actualizaciones")
            }

            Section {
                Button(role: .none) {
                    ThumbnailStore.shared.clearAll()
                    browser.reload()
                    browser.statusMessage = "Caché de miniaturas limpia"
                } label: {
                    Label("Limpiar miniaturas", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } header: {
                Text("Caché")
            } footer: {
                Text("Si un icono de vídeo o imagen se ve raro, limpia aquí. Al actualizar la app también se limpia.")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var ollamaStatusLabel: String {
        if ollama.isReady { return "Activo · \(ollama.selectedModel)" }
        if ollama.enabled && !ollama.available { return "Activado, pero Ollama no responde" }
        if ollama.available { return "Detectado — aún no activado" }
        return "Apagado · solo reglas y atajos"
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
}

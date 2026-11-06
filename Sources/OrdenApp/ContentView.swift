import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel

    /// Ancho fijo: el sidebar nunca se colapsa al achicar la ventana.
    private let sidebarWidth: CGFloat = 212

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(OrdenTheme.windowFill)

            Divider().opacity(0.35)

            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(OrdenTheme.windowFill)
        .searchable(text: $browser.searchText, placement: .toolbar, prompt: "Filtrar en esta carpeta")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: browser.goUp) {
                    Label("Arriba", systemImage: "chevron.backward")
                }
                .help("Carpeta superior (⌘↑)")
            }
            ToolbarItem(placement: .principal) {
                Text(shortPath(browser.currentPath))
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    browser.promptNewFolder()
                } label: {
                    Label("Nueva carpeta", systemImage: "folder.badge.plus")
                }
                .help("Crear carpeta aquí (⇧⌘N)")

                Toggle(isOn: $browser.multiSelectMode) {
                    Label("Varios", systemImage: "checkmark.circle")
                }
                .toggleStyle(.button)
                .help("Clic = agregar/quitar sin ⌘")

                Button {
                    browser.selectAllVisible()
                } label: {
                    Label("Todos", systemImage: "checklist")
                }

                Button {
                    browser.cancelSelection()
                } label: {
                    Label("Ninguno", systemImage: "xmark.circle")
                }
                .help("Esc — cancelar selección")
                .disabled(browser.selectedIDs.isEmpty)

                Button {
                    browser.openSelection()
                } label: {
                    Label("Abrir", systemImage: "arrow.up.forward.app")
                }
                .disabled(browser.selectedIDs.isEmpty)

                Button {
                    browser.quickLookSelection()
                } label: {
                    Label("Vista rápida", systemImage: "eye")
                }
                .disabled(browser.selectedIDs.isEmpty)

                Button(action: browser.reload) {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
            }
        }
        .alert("Nueva carpeta", isPresented: $browser.showNewFolderDialog) {
            TextField("Nombre", text: $browser.nameDraft)
            Button("Crear") { browser.createFolderFromDraft() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se crea dentro de \(shortPath(browser.currentPath))")
        }
        .alert("Renombrar", isPresented: $browser.showRenameDialog) {
            TextField("Nombre", text: $browser.nameDraft)
            Button("Guardar") { browser.commitRenameFromDraft() }
            Button("Cancelar", role: .cancel) { browser.renameTargetPath = nil }
        }
        .onKeyPress(.space) {
            browser.quickLookSelection()
            return .handled
        }
        .onKeyPress(keys: [.downArrow], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            browser.openSelection()
            return .handled
        }
        .onKeyPress(keys: [.delete], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            browser.moveSelectionToTrash()
            return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            // Return = renombrar (Finder); ⌘↓ ya abre
            guard !press.modifiers.contains(.command) else { return .ignored }
            guard browser.selectedIDs.count == 1 else { return .ignored }
            browser.promptRename()
            return .handled
        }
        .onKeyPress(.escape) {
            browser.cancelSelection()
            return .handled
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

            FileBrowserPane()
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            DropShelfView()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            if let status = browser.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
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
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(browser.scopeBadge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(browser.hasFolderOverride ? .orange : .secondary)
            }

            Spacer(minLength: 8)

            if browser.cleanupMode {
                Button {
                    browser.exitCleanupMode()
                } label: {
                    Label("Salir limpieza", systemImage: "xmark.circle")
                }
                .controlSize(.regular)
            } else {
                Button {
                    browser.showHeaviestForCleanup()
                } label: {
                    Label("Pesados", systemImage: "gauge.with.dots.needle.67percent")
                }
                .help("Ordena por peso para ver qué limpia más espacio")
                .controlSize(.regular)
            }

            Button {
                browser.useDownloadsStyleEverywhere()
            } label: {
                Label("En todas partes", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)
            .tint(OrdenTheme.accent)
            .controlSize(.regular)

            Menu {
                Section("Cambiar orden (solo esta carpeta)") {
                    sortButtons(scope: .thisFolder)
                }
                Divider()
                Button("Usar este orden en todas partes") {
                    browser.saveCurrentAsGlobalDefault()
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
                Button("Solo esta carpeta") {
                    browser.applyRule(browser.rule, scope: .thisFolder)
                }
                Button("Default en todas") {
                    browser.applyRule(browser.rule, scope: .everywhere)
                }
            } label: {
                Label("Guardar", systemImage: "square.and.arrow.down")
            }
            .menuStyle(.borderedButton)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

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
        Button("Más pesados primero (limpieza)") {
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

// MARK: - Stats / cleanup

struct FolderStatsBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(browser.folderTotalLabel, systemImage: "externaldrive.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                if browser.isMeasuringSizes {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("· \(browser.entries.count) elementos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    browser.copyCurrentFolderPath()
                } label: {
                    Label(browser.currentPath, systemImage: "doc.on.doc")
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Clic para copiar la ruta de esta carpeta")
            }

            // Solo en modo limpieza — evita una segunda franja permanente
            if browser.cleanupMode {
                HStack(spacing: 8) {
                    Text("Top peso:")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(browser.heaviestPreview.prefix(4)) { entry in
                        Text("\(entry.name) (\(FolderSizer.format(entry.size)))")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Acciones tipo Finder

struct FileActionsBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                browser.promptNewFolder()
            } label: {
                Label("Nueva carpeta", systemImage: "folder.badge.plus")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(OrdenTheme.accent)
            .controlSize(.regular)
            .help("⇧⌘N")

            Button {
                browser.promptRename()
            } label: {
                Label("Renombrar", systemImage: "pencil")
            }
            .controlSize(.regular)
            .disabled(browser.selectedIDs.count != 1)

            Button {
                browser.duplicateSelection()
            } label: {
                Label("Duplicar", systemImage: "plus.square.on.square")
            }
            .controlSize(.regular)
            .disabled(browser.selectedIDs.isEmpty)

            Button {
                browser.copySelectionToPasteboard()
            } label: {
                Label("Copiar", systemImage: "doc.on.doc")
            }
            .controlSize(.regular)
            .disabled(browser.selectedIDs.isEmpty)
            .help("Copia archivos al portapapeles (⌘C)")

            Button {
                browser.pasteFromPasteboard()
            } label: {
                Label("Pegar", systemImage: "doc.on.clipboard")
            }
            .controlSize(.regular)
            .help("Pega archivos aquí (⌘V)")

            Spacer(minLength: 8)

            Button(role: .destructive) {
                browser.moveSelectionToTrash()
            } label: {
                Label("Papelera", systemImage: "trash")
            }
            .controlSize(.regular)
            .disabled(browser.selectedIDs.isEmpty)
            .help("⌘⌫")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sectionHeader("Favoritos")
                ForEach(favoriteItems) { item in
                    sidebarButton(item)
                }

                sectionHeader("Ubicaciones")
                    .padding(.top, 12)
                ForEach(locationItems) { item in
                    sidebarButton(item)
                }
            }
            .padding(.bottom, 16)
            // volumesTick fuerza recalcular locationItems al conectar USB/discos
            .id(volumesTick)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrdenTheme.windowFill)
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
        var items: [SidebarItem] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let iCloud = (home as NSString).appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs"
        )
        if fm.fileExists(atPath: iCloud) {
            items.append(SidebarItem(
                id: "loc-icloud",
                title: "iCloud Drive",
                path: iCloud,
                systemImage: "icloud.fill"
            ))
        }

        // Google Drive / Dropbox / OneDrive en CloudStorage
        let cloudRoot = (home as NSString).appendingPathComponent("Library/CloudStorage")
        if let clouds = try? fm.contentsOfDirectory(atPath: cloudRoot) {
            for name in clouds.sorted() {
                let path = (cloudRoot as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                let title: String
                let icon: String
                let lower = name.lowercased()
                if lower.contains("google") {
                    title = "Google Drive"
                    icon = "externaldrive.fill.badge.icloud"
                } else if lower.contains("dropbox") {
                    title = "Dropbox"
                    icon = "externaldrive.fill.badge.icloud"
                } else if lower.contains("onedrive") || lower.contains("one drive") {
                    title = "OneDrive"
                    icon = "externaldrive.fill.badge.icloud"
                } else {
                    title = name
                    icon = "externaldrive.fill"
                }
                items.append(SidebarItem(id: "loc-cloud-\(name)", title: title, path: path, systemImage: icon))
            }
        }

        let homeName = URL(fileURLWithPath: home).lastPathComponent
        items.append(SidebarItem(
            id: "loc-home",
            title: homeName,
            path: home,
            systemImage: "house.fill"
        ))

        items.append(SidebarItem(
            id: "loc-root",
            title: "Macintosh HD",
            path: "/",
            systemImage: "internaldrive.fill"
        ))

        // USB / discos externos / DMGs montados en /Volumes
        _ = volumesTick
        if let vols = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            for name in vols.sorted() {
                let path = "/Volumes/\(name)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                // Evita duplicar el volumen del sistema si aparece como /Volumes/Macintosh HD
                let standardized = (path as NSString).standardizingPath
                if standardized == "/" { continue }
                items.append(SidebarItem(
                    id: "loc-vol-\(name)",
                    title: name,
                    path: path,
                    systemImage: "externaldrive.fill"
                ))
            }
        }

        let trash = (home as NSString).appendingPathComponent(".Trash")
        if fm.fileExists(atPath: trash) {
            items.append(SidebarItem(
                id: "loc-trash",
                title: "Basurero",
                path: trash,
                systemImage: "trash.fill"
            ))
        }

        return items
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func sidebarButton(_ item: SidebarItem) -> some View {
        Button {
            browser.navigate(to: item.path)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.body)
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 22, alignment: .center)
                Text(item.title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive(item.path)
                    ? OrdenTheme.accent.opacity(0.22)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help(item.path)
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

    /// Altura aproximada por fila (nombre + ruta + padding). Marquee por índice, sin GeometryReader.
    private let rowHeight: CGFloat = 52

    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBase: Set<String> = []
    @State private var marqueeAdditive = false

    var body: some View {
        VStack(spacing: 0) {
            if let error = browser.errorMessage {
                ContentUnavailableView(
                    "No se pudo abrir",
                    systemImage: "exclamationmark.folder",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.35)

                if browser.visibleEntries.isEmpty {
                    ContentUnavailableView(
                        "Vacío",
                        systemImage: "folder",
                        description: Text("No hay elementos con este filtro.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(browser.visibleEntries.enumerated()), id: \.element.id) { index, entry in
                                FileRowButton(entry: entry, zebra: index.isMultiple(of: 2))
                                    .frame(minHeight: rowHeight)
                            }
                            // Zona vacía: clic = deseleccionar; arrastre = marquee hacia arriba
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 320)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    browser.cancelSelection()
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .coordinateSpace(name: "fileList")
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
                        .highPriorityGesture(marqueeGesture)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // Clic en el fondo del scroll (márgenes / vacío visible) también cancela
                    .onTapGesture {
                        browser.cancelSelection()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: browser.selectionCancelToken) { _, _ in
            resetMarquee()
        }
    }

    private func resetMarquee() {
        marqueeStart = nil
        marqueeCurrent = nil
        marqueeBase = []
    }

    private var marqueeRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: max(abs(current.x - start.x), 1),
            height: max(abs(current.y - start.y), 1)
        )
    }

    private var listContentHeight: CGFloat {
        CGFloat(browser.visibleEntries.count) * rowHeight
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("fileList"))
            .onChanged { value in
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                    marqueeCurrent = value.location
                    let flags = NSEvent.modifierFlags
                    marqueeAdditive = flags.contains(.command) || flags.contains(.shift)
                    marqueeBase = marqueeAdditive ? browser.selectedIDs : []
                    if !marqueeAdditive {
                        browser.clearSelection()
                    }
                }
                marqueeCurrent = value.location
                applyMarquee()
            }
            .onEnded { _ in
                applyMarquee()
                resetMarquee()
            }
    }

    private func applyMarquee() {
        guard let start = marqueeStart, let current = marqueeCurrent else { return }
        let entries = browser.visibleEntries
        guard !entries.isEmpty else { return }

        let y0 = min(start.y, current.y)
        let y1 = max(start.y, current.y)
        let contentH = listContentHeight

        // Rectángulo solo en el vacío debajo de los archivos → nada
        if y0 >= contentH {
            browser.applyMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            return
        }

        let first = max(0, Int(floor(y0 / rowHeight)))
        let last = min(entries.count - 1, Int(floor((min(y1, contentH) - 0.001) / rowHeight)))
        guard first <= last else {
            browser.applyMarqueeSelection(hitIDs: [], base: marqueeBase, additive: marqueeAdditive)
            return
        }
        let hits = Set(entries[first...last].map(\.id))
        browser.applyMarqueeSelection(hitIDs: hits, base: marqueeBase, additive: marqueeAdditive)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                browser.toggleSelectAllVisible()
            } label: {
                Image(systemName: browser.allVisibleSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(OrdenTheme.accent)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help("Seleccionar / quitar todos")

            Text("Nombre / ruta")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Tipo")
                .frame(width: 100, alignment: .leading)
            Text("Agregado")
                .frame(width: 130, alignment: .trailing)
            Text("Tamaño")
                .frame(width: 84, alignment: .trailing)
            Color.clear.frame(width: 28)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct FileRowButton: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry
    let zebra: Bool

    private var isSelected: Bool {
        browser.selectedIDs.contains(entry.id)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                browser.toggleSelection(entry.id)
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

            Button(action: selectRow) {
                HStack(alignment: .center, spacing: 12) {
                    FileTypeIcon(category: entry.category, size: 17)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name)
                            .font(.body)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(entry.path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(entry.category.labelSpanish)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(entry.dateAdded, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .trailing)
                    Text(sizeLabel)
                        .font(.caption.monospacedDigit().weight(entry.size > 100_000_000 ? .semibold : .regular))
                        .foregroundStyle(entry.size > 500_000_000 ? .orange : .secondary)
                        .frame(width: 84, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .background(rowBackground)
        .contextMenu {
            Button("Abrir") {
                browser.selectOnly(entry.id)
                browser.open(entry)
            }
            Button("Renombrar") {
                browser.selectOnly(entry.id)
                browser.promptRename()
            }
            Button("Duplicar") {
                if !browser.selectedIDs.contains(entry.id) {
                    browser.selectOnly(entry.id)
                }
                browser.duplicateSelection()
            }
            Button("A bandeja") {
                if !browser.selectedIDs.contains(entry.id) {
                    browser.selectOnly(entry.id)
                }
                browser.addSelectionToShelf()
            }
            Button("Vista rápida") {
                browser.selectOnly(entry.id)
                browser.quickLookSelection()
            }
            Button("Mostrar en Finder") { browser.revealInFinder(entry) }
            Button("Copiar") {
                if !browser.selectedIDs.contains(entry.id) {
                    browser.selectOnly(entry.id)
                }
                browser.copySelectionToPasteboard()
            }
            Button("Copiar ruta completa") { browser.copyPath(entry) }
            Divider()
            Button("Nueva carpeta aquí") { browser.promptNewFolder() }
            Button("Seleccionar todos") { browser.selectAllVisible() }
            Button("Quitar selección") { browser.clearSelection() }
            Divider()
            Button("Mover a la Papelera", role: .destructive) {
                if !browser.selectedIDs.contains(entry.id) {
                    browser.selectOnly(entry.id)
                }
                browser.moveSelectionToTrash()
            }
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return OrdenTheme.accent.opacity(0.28)
        }
        return zebra ? Color.primary.opacity(0.04) : Color.clear
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
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            browser.selectOnly(entry.id)
            browser.open(entry)
            return
        }

        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            browser.selectRange(to: entry.id)
        } else if browser.multiSelectMode || flags.contains(.command) {
            browser.toggleSelection(entry.id)
        } else {
            browser.selectOnly(entry.id)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        Form {
            Section("Selección") {
                Text("Clic = uno · Arrastrar (también desde vacío o desde ya seleccionado) = rectángulo · Casilla / Varios / ⌘ = varios · ⇧ = rango · Archivos a Dropover vía Bandeja")
            }
            Section("Ordena") {
                LabeledContent("Ámbito", value: browser.scopeBadge)
                Text(browser.rule.summarySpanish)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OrdenCore

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 280)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
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
                Toggle(isOn: $browser.multiSelectMode) {
                    Label("Varios", systemImage: "checkmark.circle")
                }
                .toggleStyle(.button)
                .help("Clic = agregar/quitar sin ⌘. Ideal para marcar muchos.")

                Button {
                    browser.selectAllVisible()
                } label: {
                    Label("Todos", systemImage: "checklist")
                }
                .help("Seleccionar todos los visibles")

                Button {
                    browser.clearSelection()
                } label: {
                    Label("Ninguno", systemImage: "xmark.circle")
                }
                .disabled(browser.selectedIDs.isEmpty)

                Button {
                    browser.openSelection()
                } label: {
                    Label("Abrir", systemImage: "arrow.up.forward.app")
                }
                .disabled(browser.selectedIDs.isEmpty)

                Button {
                    browser.copySelectedPaths()
                } label: {
                    Label("Copiar ruta", systemImage: "doc.on.clipboard")
                }

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
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            SortBar()
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            FolderStatsBar()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            FileBrowserPane()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            DropShelfView()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if let status = browser.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrdenTheme.windowFill)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            // Soltar en el panel = a la bandeja (y desde ahí a Dropover / otra carpeta)
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
        .ordenGlassCard(cornerRadius: 16)
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

            if browser.cleanupMode || !browser.heaviestPreview.isEmpty {
                HStack(spacing: 8) {
                    Text(browser.cleanupMode ? "Top peso ahora:" : "Más pesados:")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(browser.heaviestPreview.prefix(4)) { entry in
                        Text("\(entry.name) (\(FolderSizer.format(entry.size)))")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(OrdenTheme.accent.opacity(0.15), in: Capsule())
                            .lineLimit(1)
                            .help(entry.path)
                            .onTapGesture {
                                browser.selectedIDs = [entry.id]
                                browser.statusMessage = entry.path
                            }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        List {
            Section("Favoritos") {
                ForEach(browser.store.preferences.favorites, id: \.self) { path in
                    Button {
                        browser.navigate(to: path)
                    } label: {
                        Label(shortName(path), systemImage: icon(for: path))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        browser.currentPath == path
                            ? OrdenTheme.accent.opacity(0.22)
                            : Color.clear
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(OrdenTheme.windowFill)
        .navigationTitle("Orden")
    }

    private func shortName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func icon(for path: String) -> String {
        switch shortName(path).lowercased() {
        case "downloads": return "arrow.down.circle.fill"
        case "desktop": return "menubar.dock.rectangle"
        case "documents": return "doc.fill"
        case "projects": return "hammer.fill"
        default: return "folder.fill"
        }
    }
}

// MARK: - File pane (selección manual = siempre funciona)

struct FileBrowserPane: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        Group {
            if let error = browser.errorMessage {
                ContentUnavailableView(
                    "No se pudo abrir",
                    systemImage: "exclamationmark.folder",
                    description: Text(error)
                )
            } else if browser.visibleEntries.isEmpty {
                ContentUnavailableView(
                    "Vacío",
                    systemImage: "folder",
                    description: Text("No hay elementos con este filtro.")
                )
            } else {
                VStack(spacing: 0) {
                    header
                    Divider().opacity(0.35)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(browser.visibleEntries.enumerated()), id: \.element.id) { index, entry in
                                FileRowButton(entry: entry, zebra: index.isMultiple(of: 2))
                            }
                        }
                    }
                }
                .background(OrdenTheme.panelFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .padding(.vertical, 10)
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
            // Checkbox: siempre agrega/quita con un clic (sin ⌘)
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
        .onDrag {
            let paths = browser.dragPaths(for: entry)
            if !browser.selectedIDs.contains(entry.id) {
                browser.selectOnly(entry.id)
            }
            if let first = paths.first {
                return NSItemProvider(contentsOf: URL(fileURLWithPath: first)) ?? NSItemProvider()
            }
            return NSItemProvider()
        }
        .contextMenu {
            Button("Abrir") {
                browser.selectOnly(entry.id)
                browser.open(entry)
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
            Button("Copiar ruta completa") { browser.copyPath(entry) }
            Divider()
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
                Text("Clic = seleccionar · ⌘ clic = varios · Doble clic / Abrir = abrir")
            }
            Section("Orden") {
                LabeledContent("Ámbito", value: browser.scopeBadge)
                Text(browser.rule.summarySpanish)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
    }
}

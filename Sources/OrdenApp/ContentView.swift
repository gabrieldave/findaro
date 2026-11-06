import SwiftUI
import AppKit
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
                Button {
                    browser.openSelection()
                } label: {
                    Label("Abrir", systemImage: "arrow.up.forward.app")
                }
                .disabled(browser.selectedIDs.isEmpty)
                .keyboardShortcut(.return, modifiers: [])

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
                .padding(.bottom, 10)

            FileBrowserPane()
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

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
            Text("Nombre")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Tipo")
                .frame(width: 110, alignment: .leading)
            Text("Agregado")
                .frame(width: 140, alignment: .trailing)
            Text("Tamaño")
                .frame(width: 72, alignment: .trailing)
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
        Button {
            selectRow()
        } label: {
            HStack(spacing: 12) {
                FileTypeIcon(category: entry.category, size: 17)
                Text(entry.name)
                    .font(.body)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)
                Text(entry.category.labelSpanish)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Text(entry.dateAdded, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 140, alignment: .trailing)
                Text(sizeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .contextMenu {
            Button("Abrir") {
                browser.selectedIDs = [entry.id]
                browser.open(entry)
            }
            Button("Vista rápida") {
                browser.selectedIDs = [entry.id]
                browser.quickLookSelection()
            }
            Button("Mostrar en Finder") { browser.revealInFinder(entry) }
            Button("Copiar ruta") { browser.copyPath(entry) }
            Divider()
            Button("Mover a la Papelera", role: .destructive) {
                browser.selectedIDs = [entry.id]
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
        entry.isDirectory
            ? "—"
            : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }

    private func selectRow() {
        // Doble clic: abrir.
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            browser.selectedIDs = [entry.id]
            browser.open(entry)
            return
        }

        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if browser.selectedIDs.contains(entry.id) {
                browser.selectedIDs.remove(entry.id)
            } else {
                browser.selectedIDs.insert(entry.id)
            }
        } else if flags.contains(.shift), let anchor = browser.selectedIDs.first {
            stretchSelection(from: anchor, to: entry.id)
        } else {
            browser.selectedIDs = [entry.id]
        }
        browser.statusMessage = "\(browser.selectedIDs.count) seleccionado(s) — \(entry.name)"
    }

    private func stretchSelection(from anchorID: String, to endID: String) {
        let ids = browser.visibleEntries.map(\.id)
        guard let a = ids.firstIndex(of: anchorID), let b = ids.firstIndex(of: endID) else {
            browser.selectedIDs = [endID]
            return
        }
        let range = a <= b ? a...b : b...a
        browser.selectedIDs = Set(ids[range])
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

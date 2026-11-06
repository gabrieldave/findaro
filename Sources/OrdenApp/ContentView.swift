import SwiftUI
import OrdenCore

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
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
                    .help(browser.currentPath)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: browser.reload) {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
                Button {
                    browser.quickLookSelection()
                } label: {
                    Label("Vista rápida", systemImage: "eye")
                }
                .disabled(browser.selectedIDs.isEmpty)
            }
        }
        .onKeyPress(.return) {
            browser.openSelection()
            return .handled
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

            FileListView()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if let status = browser.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
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
            .help("Estilo Descargas como default global")

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
            .controlSize(.regular)

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
            .controlSize(.regular)
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
        Button("Modificado · reciente primero") {
            browser.applyRule(
                SortRule(keys: [.dateModified(ascending: false)], foldersFirst: true),
                scope: scope
            )
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
                            ? OrdenTheme.accent.opacity(0.18)
                            : Color.clear
                    )
                }
            }
        }
        .listStyle(.sidebar)
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

// MARK: - File list (selección nativa; sin gestos que la rompan)

struct FileListView: View {
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
                List(selection: $browser.selectedIDs) {
                    ForEach(browser.visibleEntries) { entry in
                        FileRowView(entry: entry)
                            .tag(entry.id)
                            .contextMenu { rowMenu(entry) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.background.opacity(0.55))
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rowMenu(_ entry: FileEntry) -> some View {
        Button("Abrir") { browser.open(entry) }
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

struct FileRowView: View {
    @EnvironmentObject private var browser: BrowserModel
    let entry: FileEntry

    var body: some View {
        HStack(spacing: 12) {
            FileTypeIcon(category: entry.category, size: 18)

            Text(entry.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // simultaneousGesture no bloquea la selección del List
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                browser.open(entry)
            }
        )
    }

    private var sizeLabel: String {
        entry.isDirectory
            ? "—"
            : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        Form {
            Section("Dos modos de orden") {
                Text("1. Default global — botón «En todas partes».")
                Text("2. Orden propio — solo esta carpeta; el resto sigue el global.")
                    .foregroundStyle(.secondary)
            }
            Section("Ahora") {
                LabeledContent("Ámbito", value: browser.scopeBadge)
                Text(browser.rule.summarySpanish)
            }
            Section("Atajos") {
                LabeledContent("Abrir", value: "Return o doble clic")
                LabeledContent("Vista rápida", value: "Space")
                LabeledContent("Papelera", value: "⌘⌫")
                LabeledContent("Multiselección", value: "⌘ clic / ⇧ clic")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 340)
    }
}

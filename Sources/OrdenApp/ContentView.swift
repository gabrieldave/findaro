import SwiftUI
import OrdenCore

struct ContentView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                SortBar()
                Divider()
                FileTableView()
            }
        }
        .searchable(text: $browser.searchText, prompt: "Filtrar en esta carpeta")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: browser.goUp) {
                    Label("Arriba", systemImage: "chevron.up")
                }
                .help("Carpeta superior")
            }
            ToolbarItem(placement: .principal) {
                Text(browser.currentPath.replacingOccurrences(
                    of: FileManager.default.homeDirectoryForCurrentUser.path,
                    with: "~"
                ))
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: browser.reload) {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct SortBar: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Text(browser.ruleSummary)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            Menu("Ordenar") {
                Button("Nombre A→Z") {
                    browser.applyRule(
                        SortRule(keys: [.name(ascending: true)], foldersFirst: true),
                        saveAsFolderDefault: true
                    )
                }
                Button("Nombre Z→A") {
                    browser.applyRule(
                        SortRule(keys: [.name(ascending: false)], foldersFirst: true),
                        saveAsFolderDefault: true
                    )
                }
                Divider()
                Button("Agregado · reciente primero") {
                    browser.applyRule(
                        SortRule(keys: [.dateAdded(ascending: false)], foldersFirst: true),
                        saveAsFolderDefault: true
                    )
                }
                Button("Modificado · reciente primero") {
                    browser.applyRule(
                        SortRule(keys: [.dateModified(ascending: false)], foldersFirst: true),
                        saveAsFolderDefault: true
                    )
                }
                Button("Tamaño · grandes primero") {
                    browser.applyRule(
                        SortRule(keys: [.size(ascending: false)], foldersFirst: true),
                        saveAsFolderDefault: true
                    )
                }
                Divider()
                Button("Clase + Nombre") {
                    browser.applyRule(
                        SortRule(
                            keys: [.kind(ascending: true), .name(ascending: true)],
                            foldersFirst: true
                        ),
                        saveAsFolderDefault: true
                    )
                }
                Toggle(
                    "Carpetas arriba",
                    isOn: Binding(
                        get: { browser.rule.foldersFirst },
                        set: { on in
                            var r = browser.rule
                            r.foldersFirst = on
                            browser.applyRule(r, saveAsFolderDefault: true)
                        }
                    )
                )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

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
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func shortName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func icon(for path: String) -> String {
        let name = shortName(path).lowercased()
        switch name {
        case "downloads": return "arrow.down.circle"
        case "desktop": return "menubar.dock.rectangle"
        case "documents": return "doc"
        case "projects": return "hammer"
        default: return "folder"
        }
    }
}

struct FileTableView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
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
            Table(browser.visibleEntries, selection: $browser.selectedIDs) {
                TableColumn("Nombre") { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                        Text(entry.name)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        browser.open(entry)
                    }
                    .contextMenu {
                        Button("Abrir") { browser.open(entry) }
                        Button("Mostrar en Finder") { browser.revealInFinder(entry) }
                        Button("Copiar ruta") { browser.copyPath(entry) }
                    }
                }
                .width(min: 220, ideal: 320)

                TableColumn("Clase") { entry in
                    Text(entry.kind)
                        .foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 120)

                TableColumn("Agregado") { entry in
                    Text(entry.dateAdded, format: .dateTime.day().month().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 150)

                TableColumn("Modificado") { entry in
                    Text(entry.dateModified, format: .dateTime.day().month().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 150)

                TableColumn("Tamaño") { entry in
                    Text(entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var browser: BrowserModel

    var body: some View {
        Form {
            Section("Orden global") {
                Text(browser.store.preferences.globalRule.summarySpanish)
                Text("Las carpetas con override guardan su propia regla. Orden no usa el .DS_Store del Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 420, height: 180)
    }
}

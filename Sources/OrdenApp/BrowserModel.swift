import Foundation
import SwiftUI
import OrdenCore
import AppKit
import UniformTypeIdentifiers

@MainActor
final class BrowserModel: ObservableObject {
    @Published var currentPath: String
    @Published var entries: [FileEntry] = []
    @Published var selectedIDs: Set<String> = []
    @Published var rule: SortRule
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var statusMessage: String?
    @Published var folderTotalBytes: Int64 = 0
    @Published var isMeasuringSizes = false
    @Published var cleanupMode = false
    /// Bandeja tipo Dropover: aparcas archivos y luego los mueves/copias a otra carpeta.
    @Published var shelf: [FileOps.ShelfItem] = []
    @Published var shelfDropTargeted = false
    /// Clic simple agrega/quita sin ⌘ (ideal para marcar muchos rápido).
    @Published var multiSelectMode = false
    /// Ancla para ⇧ clic (rango).
    @Published var selectionAnchorID: String?
    @Published var showNewFolderDialog = false
    @Published var showRenameDialog = false
    @Published var nameDraft = ""
    /// Ruta pendiente de renombrar (si el diálogo está abierto).
    @Published var renameTargetPath: String?
    /// Se incrementa con Esc / cancelar para resetear gestos (marquee).
    @Published var selectionCancelToken: Int = 0
    @Published var viewMode: BrowserViewMode
    /// Pilas de rutas para vista Columnas (Miller).
    @Published var columnPaths: [String] = []

    let store: PreferencesStore
    private var measureTask: Task<Void, Never>?

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let start = store.preferences.lastPath
            ?? (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent("Downloads")
        self.currentPath = start
        self.rule = store.preferences.rule(for: start)
        self.viewMode = store.preferences.viewMode
        self.columnPaths = [start]
        reload()
    }

    func setViewMode(_ mode: BrowserViewMode) {
        viewMode = mode
        store.update { $0.viewMode = mode }
        if mode == .columns {
            columnPaths = [currentPath]
        }
        objectWillChange.send()
    }

    /// Clic con ⇧ rango · ⌘ / modo Varios toggle · normal = solo ese.
    func clickSelect(_ id: String) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            selectRange(to: id)
        } else if multiSelectMode || flags.contains(.command) {
            toggleSelection(id)
        } else {
            selectOnly(id)
        }
    }

    func activateEntry(_ entry: FileEntry) {
        if entry.isDirectory {
            navigate(to: entry.path)
        } else {
            open(entry)
        }
    }

    /// En columnas: abre carpeta en la columna siguiente.
    func openInColumns(_ entry: FileEntry, columnIndex: Int) {
        guard entry.isDirectory else {
            selectOnly(entry.id)
            open(entry)
            return
        }
        var next = Array(columnPaths.prefix(columnIndex + 1))
        next.append(entry.path)
        columnPaths = next
        currentPath = entry.path
        selectedIDs = []
        selectionAnchorID = nil
        if !cleanupMode {
            rule = store.preferences.rule(for: entry.path)
        }
        store.update { $0.lastPath = entry.path }
        reload()
    }

    var visibleEntries: [FileEntry] {
        let base = SortEngine.sort(entries, by: rule)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    var selectedEntries: [FileEntry] {
        visibleEntries.filter { selectedIDs.contains($0.id) }
    }

    var ruleSummary: String { rule.summarySpanish }

    var hasFolderOverride: Bool {
        store.preferences.hasOverride(for: currentPath)
    }

    var scopeBadge: String {
        hasFolderOverride ? "Solo esta carpeta" : "Default global"
    }

    var folderTotalLabel: String {
        if isMeasuringSizes && folderTotalBytes == 0 {
            return "Midiendo peso…"
        }
        return "Carpeta: \(FolderSizer.format(folderTotalBytes))"
    }

    var heaviestPreview: [FileEntry] {
        entries
            .filter { !$0.isDirectory || $0.size > 0 }
            .sorted { $0.size > $1.size }
            .prefix(8)
            .map { $0 }
    }

    var allVisibleSelected: Bool {
        let ids = visibleEntries.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { selectedIDs.contains($0) }
    }

    func selectOnly(_ id: String) {
        selectedIDs = [id]
        selectionAnchorID = id
        refreshSelectionStatus()
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        selectionAnchorID = id
        refreshSelectionStatus()
    }

    func selectRange(to id: String) {
        let ids = visibleEntries.map(\.id)
        let anchor = selectionAnchorID ?? selectedIDs.first ?? id
        guard let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: id) else {
            selectOnly(id)
            return
        }
        let range = a <= b ? a...b : b...a
        selectedIDs = Set(ids[range])
        refreshSelectionStatus()
    }

    /// Selección tipo Finder (rectángulo / marquee).
    func applyMarqueeSelection(hitIDs: Set<String>, base: Set<String>, additive: Bool) {
        if additive {
            selectedIDs = base.union(hitIDs)
        } else {
            selectedIDs = hitIDs
        }
        if let last = hitIDs.first {
            selectionAnchorID = last
        }
        refreshSelectionStatus()
    }

    func selectAllVisible() {
        selectedIDs = Set(visibleEntries.map(\.id))
        selectionAnchorID = visibleEntries.first?.id
        refreshSelectionStatus()
    }

    func clearSelection() {
        selectedIDs = []
        selectionAnchorID = nil
        statusMessage = "Nada seleccionado"
    }

    /// Esc: quita selección y cancela marquee / gestos a medias.
    func cancelSelection() {
        clearSelection()
        selectionCancelToken &+= 1
        statusMessage = "Selección cancelada"
    }

    func toggleSelectAllVisible() {
        if allVisibleSelected {
            clearSelection()
        } else {
            selectAllVisible()
        }
    }

    private func refreshSelectionStatus() {
        let n = selectedIDs.count
        if n == 0 {
            statusMessage = "Nada seleccionado"
        } else if n == 1, let name = selectedEntries.first?.name {
            statusMessage = "1 seleccionado — \(name)"
        } else {
            statusMessage = "\(n) seleccionados"
        }
    }

    func reload() {
        measureTask?.cancel()
        do {
            entries = try DirectoryLoader.load(path: currentPath)
            errorMessage = nil
            folderTotalBytes = FolderSizer.sum(entries.filter { !$0.isDirectory })
            startMeasuringSizes()
        } catch {
            entries = []
            folderTotalBytes = 0
            errorMessage = error.localizedDescription
        }
    }

    func navigate(to path: String) {
        currentPath = path
        if !cleanupMode {
            rule = store.preferences.rule(for: path)
        }
        selectedIDs = []
        selectionAnchorID = nil
        searchText = ""
        statusMessage = nil
        columnPaths = [path]
        store.update { $0.lastPath = path }
        reload()
    }

    func goUp() {
        let parent = (currentPath as NSString).deletingLastPathComponent
        guard parent != currentPath, !parent.isEmpty else { return }
        navigate(to: parent)
    }

    func navigateToDownloads() {
        navigate(to: home("Downloads"))
    }

    func navigateToDesktop() {
        navigate(to: home("Desktop"))
    }

    func navigateToDocuments() {
        navigate(to: home("Documents"))
    }

    // MARK: - Favoritos (accesos directos)

    func isFavorite(_ path: String) -> Bool {
        let target = (path as NSString).standardizingPath
        return store.preferences.favorites.contains {
            ($0 as NSString).standardizingPath == target
        }
    }

    func addFavorite(_ path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            statusMessage = "Solo se pueden favoritar carpetas"
            return
        }
        let standardized = (path as NSString).standardizingPath
        if isFavorite(standardized) {
            statusMessage = "Ya está en Favoritos"
            return
        }
        store.update { $0.favorites.append(standardized) }
        objectWillChange.send()
        statusMessage = "Favorito: \(URL(fileURLWithPath: standardized).lastPathComponent)"
    }

    func removeFavorite(_ path: String) {
        let target = (path as NSString).standardizingPath
        store.update { prefs in
            prefs.favorites.removeAll { ($0 as NSString).standardizingPath == target }
        }
        objectWillChange.send()
        statusMessage = "Quitado de Favoritos"
    }

    func addCurrentFolderToFavorites() {
        addFavorite(currentPath)
    }

    /// Diálogo para elegir cualquier carpeta y fijarla arriba.
    func pickFolderAsFavorite() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Elige una carpeta para Favoritos"
        panel.prompt = "Añadir"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFavorite(url.path)
    }

    func addSelectionToFavorites() {
        let folders = selectedEntries.filter(\.isDirectory)
        guard !folders.isEmpty else {
            statusMessage = "Selecciona una carpeta (o usa la carpeta actual)"
            return
        }
        for folder in folders {
            addFavorite(folder.path)
        }
        if folders.count > 1 {
            statusMessage = "\(folders.count) carpetas en Favoritos"
        }
    }

    /// Botón «A Favoritos»: carpetas seleccionadas, o la carpeta actual.
    func addFoldersToFavoritesFromUI() {
        let folders = selectedEntries.filter(\.isDirectory)
        if !folders.isEmpty {
            addSelectionToFavorites()
            return
        }
        addCurrentFolderToFavorites()
    }

    /// Soltar carpetas desde Finder sobre Favoritos (opcional).
    @discardableResult
    func importFavoritesFromProviders(_ providers: [NSItemProvider]) -> Bool {
        var paths: [String] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    paths.append(url.path)
                } else if let url = item as? URL {
                    paths.append(url.path)
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            var added = 0
            for path in paths {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    if !self.isFavorite(path) {
                        self.addFavorite(path)
                        added += 1
                    }
                }
            }
            if added == 0 && !paths.isEmpty {
                self.statusMessage = "Suelta carpetas (no archivos sueltos)"
            } else if added > 1 {
                self.statusMessage = "\(added) carpetas en Favoritos"
            }
        }
        return true
    }

    func applyRule(_ newRule: SortRule, scope: SortSaveScope) {
        cleanupMode = (newRule == .heaviestFirst)
        rule = newRule
        store.update { prefs in
            switch scope {
            case .thisFolder:
                prefs.folderOverrides[currentPath] = newRule
            case .everywhere:
                prefs.globalRule = newRule
                prefs.folderOverrides = [:]
            }
        }
        statusMessage = scope == .everywhere
            ? "Orden aplicado en todas las carpetas"
            : "Orden guardado solo en esta carpeta"
        objectWillChange.send()
    }

    func useDownloadsStyleEverywhere() {
        cleanupMode = false
        applyRule(.downloads, scope: .everywhere)
        rule = .downloads
    }

    func useGlobalDefaultHere() {
        cleanupMode = false
        store.update { prefs in
            prefs.folderOverrides.removeValue(forKey: currentPath)
        }
        rule = store.preferences.globalRule
        statusMessage = "Esta carpeta usa el default global"
        objectWillChange.send()
    }

    func saveCurrentAsGlobalDefault() {
        applyRule(rule, scope: .everywhere)
    }

    /// Modo limpieza: lo más pesado arriba.
    func showHeaviestForCleanup() {
        cleanupMode = true
        rule = .heaviestFirst
        statusMessage = "Limpieza: archivos/carpetas más pesados arriba"
        objectWillChange.send()
    }

    func exitCleanupMode() {
        cleanupMode = false
        rule = store.preferences.rule(for: currentPath)
        statusMessage = "Volviste al orden normal"
        objectWillChange.send()
    }

    func open(_ entry: FileEntry) {
        if entry.isDirectory {
            navigate(to: entry.path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        }
    }

    func openSelection() {
        guard let first = selectedEntries.first else { return }
        open(first)
    }

    func revealInFinder(_ entry: FileEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }

    func copyPath(_ entry: FileEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.path, forType: .string)
        statusMessage = "Ruta copiada: \(entry.path)"
    }

    func copySelectedPaths() {
        let paths = selectedEntries.map(\.path)
        guard !paths.isEmpty else {
            // Si no hay selección, copia la carpeta actual.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(currentPath, forType: .string)
            statusMessage = "Ruta de carpeta copiada"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        statusMessage = paths.count == 1 ? "Ruta copiada" : "\(paths.count) rutas copiadas"
    }

    func copyCurrentFolderPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentPath, forType: .string)
        statusMessage = "Ruta de carpeta copiada"
    }

    func quickLookSelection() {
        let paths = selectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        QuickLookController.shared.toggle(paths: paths)
    }

    func moveSelectionToTrash() {
        let targets = selectedEntries
        guard !targets.isEmpty else { return }
        var moved = 0
        for entry in targets {
            let url = URL(fileURLWithPath: entry.path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                moved += 1
            } catch {
                statusMessage = "No se pudo tirar \(entry.name): \(error.localizedDescription)"
            }
        }
        selectedIDs = []
        selectionAnchorID = nil
        reload()
        if moved > 0 {
            statusMessage = moved == 1 ? "1 elemento a la Papelera" : "\(moved) elementos a la Papelera"
        }
    }

    // MARK: - Crear / renombrar / duplicar / portapapeles

    func promptNewFolder() {
        nameDraft = "Carpeta sin título"
        showNewFolderDialog = true
    }

    func createFolderFromDraft() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let path = try FileOps.createFolder(named: name, in: currentPath)
            reload()
            selectOnly(path)
            statusMessage = "Carpeta creada: \(URL(fileURLWithPath: path).lastPathComponent)"
        } catch {
            statusMessage = "No se pudo crear: \(error.localizedDescription)"
        }
    }

    func promptRename() {
        guard let entry = selectedEntries.first else {
            statusMessage = "Selecciona un ítem para renombrar"
            return
        }
        renameTargetPath = entry.path
        nameDraft = entry.name
        showRenameDialog = true
    }

    func commitRenameFromDraft() {
        guard let path = renameTargetPath else { return }
        let newName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        do {
            let newPath = try FileOps.rename(path: path, to: newName)
            reload()
            selectOnly(newPath)
            statusMessage = "Renombrado a \(newName)"
        } catch {
            statusMessage = "No se pudo renombrar: \(error.localizedDescription)"
        }
        renameTargetPath = nil
    }

    func duplicateSelection() {
        let targets = selectedEntries
        guard !targets.isEmpty else {
            statusMessage = "Selecciona algo para duplicar"
            return
        }
        var lastPath: String?
        var count = 0
        for entry in targets {
            do {
                lastPath = try FileOps.duplicate(path: entry.path)
                count += 1
            } catch {
                statusMessage = "No se pudo duplicar \(entry.name): \(error.localizedDescription)"
                reload()
                return
            }
        }
        reload()
        if let lastPath {
            selectOnly(lastPath)
        }
        statusMessage = count == 1 ? "Duplicado" : "\(count) duplicados"
    }

    /// Copia archivos (URLs) al portapapeles — pegable en Finder/Orden.
    func copySelectionToPasteboard() {
        let urls = selectedEntries.map { URL(fileURLWithPath: $0.path) as NSURL }
        guard !urls.isEmpty else {
            statusMessage = "Nada seleccionado"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls)
        statusMessage = urls.count == 1 ? "Copiado (archivo)" : "\(urls.count) archivos copiados"
    }

    func pasteFromPasteboard() {
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            statusMessage = "El portapapeles no tiene archivos"
            return
        }
        do {
            let n = try FileOps.transfer(
                paths: urls.map(\.path),
                toDirectory: currentPath,
                move: false
            )
            reload()
            statusMessage = n == 1 ? "1 archivo pegado" : "\(n) archivos pegados"
        } catch {
            statusMessage = "No se pudo pegar: \(error.localizedDescription)"
        }
    }

    var canPasteFiles: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }

    // MARK: - Bandeja (Dropover casero)

    func addSelectionToShelf() {
        let items = selectedEntries.map(FileOps.ShelfItem.init(entry:))
        guard !items.isEmpty else {
            statusMessage = "Selecciona algo para la bandeja"
            return
        }
        for item in items where !shelf.contains(where: { $0.path == item.path }) {
            shelf.append(item)
        }
        statusMessage = "Bandeja: \(shelf.count) ítem(s)"
    }

    func addPathsToShelf(_ paths: [String]) {
        for path in paths {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let item = FileOps.ShelfItem(path: path, name: name)
            if !shelf.contains(where: { $0.path == path }) {
                shelf.append(item)
            }
        }
        statusMessage = "Bandeja: \(shelf.count) ítem(s)"
    }

    func removeFromShelf(_ item: FileOps.ShelfItem) {
        shelf.removeAll { $0.path == item.path }
    }

    func clearShelf() {
        shelf.removeAll()
        statusMessage = "Bandeja vacía"
    }

    func moveShelfHere() {
        transferShelf(move: true)
    }

    func copyShelfHere() {
        transferShelf(move: false)
    }

    private func transferShelf(move: Bool) {
        let paths = shelf.map(\.path)
        guard !paths.isEmpty else {
            statusMessage = "La bandeja está vacía"
            return
        }
        do {
            let n = try FileOps.transfer(paths: paths, toDirectory: currentPath, move: move)
            if move {
                shelf.removeAll { paths.contains($0.path) }
            }
            reload()
            statusMessage = move
                ? "Movidos \(n) a esta carpeta"
                : "Copiados \(n) a esta carpeta"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Paths para arrastrar a Dropover / Finder / otras apps.
    func dragPaths(for entry: FileEntry) -> [String] {
        if selectedIDs.contains(entry.id), selectedIDs.count > 1 {
            return selectedEntries.map(\.path)
        }
        return [entry.path]
    }

    func importDroppedFiles(providers: [NSItemProvider]) -> Bool {
        var collected: [String] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collected.append(url.path)
                } else if let url = item as? URL {
                    collected.append(url.path)
                }
            }
        }
        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            self.addPathsToShelf(collected)
        }
        return true
    }

    private func startMeasuringSizes() {
        let snapshot = entries
        let path = currentPath
        isMeasuringSizes = true

        measureTask = Task.detached(priority: .utility) {
            var updated = snapshot
            var total: Int64 = 0

            for index in updated.indices {
                if Task.isCancelled { return }
                let entry = updated[index]
                let bytes = FolderSizer.measure(
                    path: entry.path,
                    isDirectory: entry.isDirectory
                )
                updated[index] = FileEntry(
                    path: entry.path,
                    name: entry.name,
                    isDirectory: entry.isDirectory,
                    size: bytes,
                    dateModified: entry.dateModified,
                    dateCreated: entry.dateCreated,
                    dateAdded: entry.dateAdded,
                    kind: entry.kind
                )
                total += bytes
            }

            if Task.isCancelled { return }
            let folderTotal = FolderSizer.recursiveDirectorySize(at: path)

            await MainActor.run {
                guard self.currentPath == path else { return }
                self.entries = updated
                self.folderTotalBytes = max(folderTotal, total)
                self.isMeasuringSizes = false
                self.objectWillChange.send()
            }
        }
    }

    private func home(_ component: String) -> String {
        (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent(component)
    }
}

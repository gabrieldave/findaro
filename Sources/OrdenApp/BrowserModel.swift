import Foundation
import SwiftUI
import OrdenCore
import AppKit
import UniformTypeIdentifiers

struct OpenWithApp: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var currentPath: String
    @Published var entries: [FileEntry] = []
    @Published var selectedIDs: Set<String> = []
    @Published var rule: SortRule
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    /// `nil` = todos los tipos. Filtra la lista visible por categoría.
    @Published var categoryFilter: FileCategory? = nil
    @Published var statusMessage: String?
    @Published var folderTotalBytes: Int64 = 0
    @Published var isMeasuringSizes = false
    @Published var cleanupMode = false
    /// Modo exclusivo: solo ítems agregados/creados hoy en esta carpeta (descargas del día).
    @Published var downloadsTodayMode = false
    /// Atajo del asistente activo (tipo + fechas).
    @Published var activeAssistantShortcut: AssistantShortcut? = nil
    @Published var assistantShortcuts: [AssistantShortcut] = []
    /// Historial tipo Explorer/Finder: atrás / adelante.
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    private var backStack: [String] = []
    private var forwardStack: [String] = []
    /// ⌘+clic: modo naranja sticky «listo para mover». Queda hasta Esc / Cancelar / drop.
    @Published private(set) var fileDragArmedPaths: [String] = []
    /// Paths en progreso de armado (toda la selección si hay varias).
    @Published private(set) var fileDragArmingPaths: Set<String> = []
    @Published private(set) var fileDragArmProgress: Double = 0
    private var armingProgressTask: Task<Void, Never>?
    /// Path donde empezó el hold (para cancelar solo ese gesto).
    private var fileDragArmingPrimaryPath: String?

    /// ¿Este path está en el hold actual?
    func isFileDragArming(path: String) -> Bool {
        fileDragArmingPaths.contains(path)
    }

    /// Compat: algún path armándose.
    var fileDragArmingPath: String? { fileDragArmingPrimaryPath }
    /// Bandeja tipo Dropover: aparcas archivos y luego los mueves/copias a otra carpeta.
    @Published var shelf: [FileOps.ShelfItem] = []
    @Published var shelfDropTargeted = false
    /// Carpeta bajo el cursor al arrastrar (drop para meter adentro).
    @Published var folderDropTargetPath: String?

    /// Historial para ⌘Z (mover/copiar).
    private var undoStack: [UndoRecord] = []
    private let undoLimit = 30

    private enum UndoRecord {
        /// Mover: deshacer = devolver `to` → `from`.
        case moved(pairs: [FileOps.TransferPair])
        /// Copiar: deshacer = tirar los `to` a la Papelera.
        case copied(created: [String])
    }
    /// Clic simple agrega/quita sin ⌘ (ideal para marcar muchos rápido).
    @Published var multiSelectMode = false
    /// Ancla para ⇧ clic / ⇧ flechas (rango). No se mueve al extender.
    @Published var selectionAnchorID: String?
    /// Tras ⌘+clic del monitor AppKit, ignorar el clic SwiftUI que llega sin modificadores y te deja 1 solo.
    private var ignorePlainSelectUntil: Date?
    /// Cursor de teclado: fila activa al navegar con flechas (con o sin ⇧).
    @Published var selectionFocusID: String?
    @Published var showNewFolderDialog = false
    @Published var showNewFileDialog = false
    @Published var showRenameDialog = false
    @Published var nameDraft = ""
    /// Ruta pendiente de renombrar (si el diálogo está abierto).
    @Published var renameTargetPath: String?
    /// Se incrementa con Esc / cancelar para resetear gestos (marquee).
    @Published var selectionCancelToken: Int = 0
    @Published var viewMode: BrowserViewMode
    /// Mostrar `/ruta/completa` bajo el nombre en cada fila.
    @Published var showRowPaths: Bool
    /// Perfil Explorer: Enter abre, F2 renombra.
    @Published var explorerKeyboardProfile: Bool
    /// Pilas de rutas para vista Columnas (Miller).
    @Published var columnPaths: [String] = []

    // MARK: Ir a carpeta / path bar
    @Published var showGoToFolderDialog = false
    @Published var goToFolderDraft = ""

    // MARK: Búsqueda profunda
    @Published var deepSearchHits: [SearchHit] = []
    @Published var deepSearchProgress: SearchProgress?
    @Published var deepSearchRunning = false
    @Published var showDeepSearchPanel = false
    @Published var deepSearchQuery: String = ""
    @Published var deepSearchRoot: String = ""
    @Published var showDeepSearchDialog = false
    @Published var deepSearchDraft = ""
    private var deepSearchTask: Task<Void, Never>?

    // MARK: Smart merge
    @Published var pendingMergePreview: FolderMerge.Preview?
    @Published var pendingMergeMove = false

    // MARK: Asistente
    @Published var showAssistantPanel = false
    @Published var showOllamaSetupDialog = false
    @Published var showFolderHandlerSetupDialog = false
    @Published var folderHandlerSetupResult: FolderHandlerSetupResult = .readyForOpenWith(appPath: "")
    @Published var agentPlan: AgentPlan?

    func runFolderHandlerSetup() {
        let result = OpenFolderBridge.prepareFolderOpener()
        folderHandlerSetupResult = result
        showFolderHandlerSetupDialog = true
        switch result {
        case .alreadyDefault:
            statusMessage = "Ordena ya está como app de carpetas"
        case .readyForOpenWith:
            statusMessage = "Ordena lista en «Abrir con» — falta elegir Siempre (límite de Apple)"
        case .appMissing:
            statusMessage = "No encuentro Ordena.app en Aplicaciones"
        }
    }
    @Published var agentLog: [String] = []
    /// Conversación legible (no terminal en miniatura).
    @Published var agentMessages: [AgentChatMessage] = []
    @Published var pendingAgentApproval: AgentPlan?

    struct AgentChatMessage: Identifiable, Equatable {
        enum Role: Equatable {
            case user
            case assistant
        }
        let id: UUID
        let role: Role
        let text: String

        init(id: UUID = UUID(), role: Role, text: String) {
            self.id = id
            self.role = role
            self.text = text
        }
    }

    let store: PreferencesStore
    private var measureTask: Task<Void, Never>?
    private let folderWatcher = FolderWatcher()
    private var ignoreWatcherUntil: Date?

    struct PathSegment: Equatable, Identifiable {
        var id: String { path }
        let title: String
        let path: String
    }

    var pathSegments: [PathSegment] {
        let standardized = (currentPath as NSString).standardizingPath
        if standardized == "/" {
            return [PathSegment(title: "/", path: "/")]
        }
        var parts: [PathSegment] = []
        var built = ""
        for component in standardized.split(separator: "/") {
            built += "/" + component
            let title: String
            if built == FileManager.default.homeDirectoryForCurrentUser.path {
                title = "~"
            } else {
                title = String(component)
            }
            parts.append(PathSegment(title: title, path: built))
        }
        return parts
    }

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let start = store.preferences.lastPath
            ?? (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent("Downloads")
        self.currentPath = start
        self.rule = store.preferences.rule(for: start)
        self.viewMode = store.preferences.viewMode
        self.showRowPaths = store.preferences.showRowPaths
        self.explorerKeyboardProfile = store.preferences.explorerKeyboardProfile
        self.assistantShortcuts = store.preferences.assistantShortcuts
        self.columnPaths = [start]
        OllamaClient.shared.applyPreferences(store.preferences)
        folderWatcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.handleFolderWatcherEvent()
            }
        }
        reload()
        refreshHistoryFlags()
        startWatchingCurrentFolder()
    }

    private func handleFolderWatcherEvent() {
        if let until = ignoreWatcherUntil, until > Date() { return }
        let before = Set(entries.map(\.id))
        reload(preserveSelection: true, fromWatcher: true)
        let after = Set(entries.map(\.id))
        if before != after {
            statusMessage = "Carpeta actualizada"
        }
    }

    private func startWatchingCurrentFolder() {
        folderWatcher.watch(path: currentPath)
    }

    /// Tras ops locales: ignora el watcher un momento para no recargar dos veces.
    func noteLocalFileMutation(quietSeconds: TimeInterval = 0.7) {
        ignoreWatcherUntil = Date().addingTimeInterval(quietSeconds)
    }

    func reload(preserveSelection: Bool = false, fromWatcher: Bool = false) {
        let previous = preserveSelection ? selectedIDs : []
        let prevFocus = selectionFocusID
        let prevAnchor = selectionAnchorID
        measureTask?.cancel()
        do {
            let loaded = try DirectoryLoader.load(path: currentPath)
            entries = SortEngine.sort(loaded, by: rule)
            errorMessage = nil
            if preserveSelection {
                selectedIDs = previous.intersection(Set(entries.map(\.id)))
                if let prevFocus, selectedIDs.contains(prevFocus) {
                    selectionFocusID = prevFocus
                } else {
                    selectionFocusID = selectedIDs.first
                }
                if let prevAnchor, selectedIDs.contains(prevAnchor) {
                    selectionAnchorID = prevAnchor
                } else {
                    selectionAnchorID = selectedIDs.first
                }
            }
            folderTotalBytes = FolderSizer.sum(entries.filter { !$0.isDirectory })
            startMeasuringSizes()
        } catch {
            entries = []
            folderTotalBytes = 0
            errorMessage = error.localizedDescription
        }
        if !fromWatcher {
            startWatchingCurrentFolder()
        }
    }

    func setViewMode(_ mode: BrowserViewMode) {
        viewMode = mode
        store.update { $0.viewMode = mode }
        if mode == .columns {
            columnPaths = [currentPath]
        }
        objectWillChange.send()
    }

    func setShowRowPaths(_ show: Bool) {
        showRowPaths = show
        store.update { $0.showRowPaths = show }
        objectWillChange.send()
    }

    /// Clic: ⇧ rango · ⌘ = **el mismo** `selectRange` + naranja · Varios/casilla · normal = uno.
    func clickSelect(_ id: String) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            selectRange(to: id)
            if hasArmedFileDrag { syncArmedWithSelection() }
        } else if flags.contains(.command) {
            commandRangeSelectForMove(to: id)
        } else if multiSelectMode {
            toggleSelection(id)
            if hasArmedFileDrag { syncArmedWithSelection() }
        } else {
            // Evita que un clic SwiftUI sin ⌘ pise el rango del monitor.
            if let until = ignorePlainSelectUntil, Date() < until { return }
            if hasArmedFileDrag { clearArmedFileDrag() }
            selectOnly(id)
        }
    }

    func noteCommandClickHandled() {
        ignorePlainSelectUntil = Date().addingTimeInterval(0.5)
    }

    /// ⌘+clic = idéntico a ⇧+clic (`selectRange` desde el ancla), y deja el grupo en naranja.
    /// Clic a clic con ⌘ sostenido: 1, luego 2, luego 3 → va creciendo el bloque, igual que ⇧.
    func commandRangeSelectForMove(to id: String) {
        noteCommandClickHandled()
        // Misma ancla que ⇧: si ya hay un solo seleccionado, ese es el origen del rango.
        if selectionAnchorID == nil {
            selectionAnchorID = selectedIDs.first ?? id
        }
        selectRange(to: id)

        armingProgressTask?.cancel()
        armingProgressTask = nil
        fileDragArmingPaths = []
        fileDragArmingPrimaryPath = nil
        fileDragArmProgress = 1
        fileDragArmedPaths = selectedEntries.map(\.path)

        statusMessage = fileDragArmedPaths.count <= 1
            ? "Listo para mover — ⌘+clic siguiente = mismo rango que ⇧ · Esc cancela"
            : "\(fileDragArmedPaths.count) listos — ⌘+clic = igual que ⇧ · arrastra · Esc"
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        objectWillChange.send()
    }

    func activateEntry(_ entry: FileEntry) {
        clearArmedFileDrag()
        if entry.isDirectory {
            navigate(to: entry.path)
            statusMessage = "Abrí carpeta: \(entry.name)"
        } else {
            open(entry)
            statusMessage = "Abrí: \(entry.name)"
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
        pushHistoryBeforeLeavingCurrent()
        currentPath = entry.path
        // Mantener selección del ítem (antes se borraba y “no funcionaba” en columnas)
        if !selectedIDs.contains(entry.id) {
            selectedIDs = [entry.id]
        }
        selectionAnchorID = entry.id
        selectionFocusID = entry.id
        if !cleanupMode {
            rule = store.preferences.rule(for: entry.path)
        }
        store.update { $0.lastPath = entry.path }
        reload()
    }

    var visibleEntries: [FileEntry] {
        let base: [FileEntry]
        if let shortcut = activeAssistantShortcut {
            let matched = entries.filter { shortcut.matches($0) }
            base = DownloadDayFilter.sortNewestFirst(matched)
        } else if downloadsTodayMode {
            // Exclusivo: oculta todo lo que no sea actividad de hoy; orden fijo (más nuevo arriba)
            let today = entries.filter { DownloadDayFilter.isActivityToday($0) }
            base = DownloadDayFilter.sortNewestFirst(today)
        } else {
            base = SortEngine.sort(entries, by: rule)
        }
        let typed: [FileEntry]
        if activeAssistantShortcut != nil {
            typed = base
        } else if let categoryFilter {
            typed = base.filter { $0.category == categoryFilter }
        } else {
            typed = base
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return typed }
        return typed.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.path.localizedCaseInsensitiveContains(q)
        }
    }

    /// Conteos por categoría en la carpeta actual (antes del filtro Tipo).
    var categoryCounts: [(category: FileCategory, count: Int)] {
        var bag: [FileCategory: Int] = [:]
        for entry in entries {
            bag[entry.category, default: 0] += 1
        }
        return bag
            .map { (category: $0.key, count: $0.value) }
            .sorted { $0.category.sortIndex < $1.category.sortIndex }
    }

    var categoryFilterLabel: String {
        if let categoryFilter {
            let n = entries.filter { $0.category == categoryFilter }.count
            return "\(categoryFilter.labelSpanish) · \(n)"
        }
        return "Todos · \(entries.count)"
    }

    func clearCategoryFilter() {
        categoryFilter = nil
    }

    var downloadsTodayCount: Int {
        entries.filter { DownloadDayFilter.isActivityToday($0) }.count
    }

    var selectedEntries: [FileEntry] {
        visibleEntries.filter { selectedIDs.contains($0.id) }
    }

    var ruleSummary: String {
        if let shortcut = activeAssistantShortcut {
            return "Atajo · \(shortcut.title) · \(visibleEntries.count)"
        }
        if downloadsTodayMode {
            return "Descargados hoy · \(downloadsTodayCount) en esta carpeta"
        }
        return rule.summarySpanish
    }

    var hasFolderOverride: Bool {
        store.preferences.hasOverride(for: currentPath)
    }

    var scopeBadge: String {
        if downloadsTodayMode {
            return "Modo exclusivo · orden normal en pausa"
        }
        return hasFolderOverride ? "Solo esta carpeta" : "Default global"
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
        selectionFocusID = id
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    /// Suma un ítem sin quitar los demás (⌘+clic / multi + naranja).
    func addToSelection(_ id: String) {
        selectedIDs.insert(id)
        if selectionAnchorID == nil {
            selectionAnchorID = id
        }
        selectionFocusID = id
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        selectionAnchorID = id
        selectionFocusID = id
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    func selectRange(to id: String) {
        let ids = visibleEntries.map(\.id)
        let anchor = selectionAnchorID ?? selectedIDs.first ?? id
        if selectionAnchorID == nil {
            selectionAnchorID = anchor
        }
        guard let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: id) else {
            selectOnly(id)
            return
        }
        let range = a <= b ? a...b : b...a
        selectedIDs = Set(ids[range])
        // El ancla se mantiene (como Finder/Explorer) para el próximo ⇧/⌘+clic.
        selectionFocusID = id
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    /// Flechas ↑↓ (y ←→ en lista): mueve el cursor. Con ⇧ extiende el rango
    /// desde el ancla, como en el Explorador de Windows (solo selección).
    func moveSelectionByKeyboard(delta: Int, extending: Bool) {
        let ids = visibleEntries.map(\.id)
        guard !ids.isEmpty else { return }

        // Sin selección: flecha baja → primero; flecha alta → último.
        if selectedIDs.isEmpty, selectionFocusID == nil {
            selectOnly(delta >= 0 ? ids[0] : ids[ids.count - 1])
            return
        }

        let cursor = selectionFocusID
            ?? selectionAnchorID
            ?? selectedIDs.first
            ?? ids[0]
        let idx = ids.firstIndex(of: cursor) ?? 0
        let next = min(max(0, idx + delta), ids.count - 1)
        let nextID = ids[next]

        if extending {
            if selectionAnchorID == nil {
                selectionAnchorID = cursor
            }
            selectRange(to: nextID)
        } else {
            selectOnly(nextID)
        }
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
            selectionFocusID = last
        }
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    func selectAllVisible() {
        selectedIDs = Set(visibleEntries.map(\.id))
        selectionAnchorID = visibleEntries.first?.id
        selectionFocusID = visibleEntries.last?.id ?? visibleEntries.first?.id
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    func clearSelection() {
        selectedIDs = []
        selectionAnchorID = nil
        selectionFocusID = nil
        if hasArmedFileDrag {
            clearArmedFileDrag()
        }
        statusMessage = "Nada seleccionado"
    }

    /// Si el naranja está ON, el grupo armado sigue la selección múltiple.
    func syncArmedWithSelection() {
        guard hasArmedFileDrag else { return }
        let paths = selectedEntries.map(\.path)
        if paths.isEmpty {
            clearArmedFileDrag()
            return
        }
        fileDragArmedPaths = paths
        objectWillChange.send()
    }

    /// Esc / Cancelar: quita selección múltiple, hold-armar, marquee y drop target.
    func cancelSelection() {
        clearArmedFileDrag()
        folderDropTargetPath = nil
        multiSelectMode = false
        clearSelection()
        selectionCancelToken &+= 1
        statusMessage = "Selección cancelada"
    }

    /// Clic en zona vacía: no cancelar si hay ⌘/⇧ (evita apagar el naranja al soltar ⌘+clic).
    func cancelSelectionFromBackgroundTap() {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.shift) { return }
        cancelSelection()
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

    func navigate(to path: String, recordHistory: Bool = true) {
        let target = (path as NSString).standardizingPath
        let current = (currentPath as NSString).standardizingPath
        guard target != current else { return }
        // Al cambiar de carpeta, quita el filtro Tipo para no “perder” archivos.
        categoryFilter = nil
        if recordHistory {
            pushHistoryBeforeLeavingCurrent()
        }
        currentPath = target
        if !cleanupMode {
            rule = store.preferences.rule(for: target)
        }
        selectedIDs = []
        selectionAnchorID = nil
        selectionFocusID = nil
        searchText = ""
        statusMessage = nil
        columnPaths = [target]
        store.update { $0.lastPath = target }
        ignoreWatcherUntil = Date().addingTimeInterval(0.6)
        reload()
        refreshHistoryFlags()
    }

    // MARK: - Ir a carpeta (⌘3)

    func promptGoToFolder() {
        goToFolderDraft = currentPath
        showGoToFolderDialog = true
    }

    func submitGoToFolder() {
        let raw = goToFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let expanded: String
        if raw == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else if raw.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expanded = (home as NSString).appendingPathComponent(String(raw.dropFirst(2)))
        } else {
            expanded = raw
        }
        let path = (expanded as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            statusMessage = "No existe esa carpeta"
            return
        }
        showGoToFolderDialog = false
        navigate(to: path)
        statusMessage = "Fui a \(path)"
    }

    // MARK: - Stubs Fase 1c–5 (compilan; UI se activa fase a fase)

    /// ⌘4 / botón Subcarpetas: si ya hay texto en el filtro, busca; si no, pide qué buscar.
    func promptDeepSearch() {
        let existing = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty {
            startDeepSearch(query: existing)
            return
        }
        deepSearchDraft = deepSearchQuery
        showDeepSearchDialog = true
    }

    func submitDeepSearchFromDialog() {
        let q = deepSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        showDeepSearchDialog = false
        searchText = q
        startDeepSearch(query: q)
    }

    func startDeepSearch(query: String? = nil) {
        let q = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            promptDeepSearch()
            return
        }
        cancelDeepSearch()
        deepSearchHits = []
        deepSearchQuery = q
        deepSearchRoot = currentPath
        deepSearchProgress = SearchProgress(currentFolder: currentPath)
        deepSearchRunning = true
        showDeepSearchPanel = true
        statusMessage = "Buscando «\(q)» en subcarpetas…"
        let root = currentPath
        deepSearchTask = Task.detached(priority: .userInitiated) {
            RecursiveSearch.run(
                query: .init(text: q, root: root),
                isCancelled: { Task.isCancelled },
                onProgress: { progress in
                    Task { @MainActor in
                        self.deepSearchProgress = progress
                        self.deepSearchRunning = !progress.done
                        if progress.done {
                            self.statusMessage = progress.matched == 0
                                ? "Sin coincidencias para «\(q)»"
                                : "\(progress.matched) resultados para «\(q)»"
                        }
                    }
                },
                onHit: { hit in
                    Task { @MainActor in
                        self.deepSearchHits.append(hit)
                    }
                }
            )
            await MainActor.run {
                self.deepSearchRunning = false
            }
        }
    }

    func cancelDeepSearch() {
        deepSearchTask?.cancel()
        deepSearchTask = nil
        deepSearchRunning = false
    }

    func clearDeepSearch() {
        cancelDeepSearch()
        deepSearchHits = []
        deepSearchProgress = nil
        deepSearchQuery = ""
        deepSearchRoot = ""
        showDeepSearchPanel = false
    }

    func openDeepSearchHit(_ hit: SearchHit) {
        if hit.isDirectory {
            navigate(to: hit.path)
        } else {
            navigate(to: (hit.path as NSString).deletingLastPathComponent)
            selectOnly(hit.path)
        }
    }

    func confirmPendingMerge(overwriteConflicts: Bool = false) {
        guard let preview = pendingMergePreview else { return }
        let asMove = pendingMergeMove
        do {
            let pairs = try FolderMerge.mergeCopy(
                source: preview.sourcePath,
                dest: preview.destPath,
                overwriteConflicts: overwriteConflicts
            )
            if !pairs.isEmpty, !overwriteConflicts {
                pushUndo(.copied(created: pairs.map(\.to)))
            }
            // Con reemplazo no deshacemos fácil el archivo pisado; solo avisamos.
            if asMove {
                let src = URL(fileURLWithPath: preview.sourcePath)
                if FileManager.default.fileExists(atPath: src.path) {
                    try FileManager.default.trashItem(at: src, resultingItemURL: nil)
                }
                shelf.removeAll {
                    ($0.path as NSString).standardizingPath == (preview.sourcePath as NSString).standardizingPath
                }
            }
            pendingMergePreview = nil
            pendingMergeMove = false
            folderDropTargetPath = nil
            clearArmedFileDrag()
            ignoreWatcherUntil = Date().addingTimeInterval(0.8)
            noteLocalFileMutation()
            reload()
            let name = URL(fileURLWithPath: preview.destPath).lastPathComponent
            if overwriteConflicts {
                statusMessage = asMove
                    ? "Fusionado reemplazando · origen a Papelera → \(name)"
                    : "Fusionado reemplazando conflictos → \(name) · \(pairs.count) ítems"
            } else {
                statusMessage = asMove
                    ? "Fusionado y origen a Papelera → \(name) · \(pairs.count) ítems · ⌘Z deshace copias"
                    : "Fusionado → \(name) · \(pairs.count) ítems · ⌘Z deshace"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func cancelPendingMerge() {
        pendingMergePreview = nil
        pendingMergeMove = false
    }

    /// Si al transferir una carpeta ya existe otra con el mismo nombre → Smart Merge.
    /// Devuelve true si abrió el preview (y no hay que transferir esos paths).
    @discardableResult
    private func offerMergeIfNeeded(paths: [String], toDirectory dest: String, move: Bool) -> [String] {
        var remaining: [String] = []
        var firstMerge: (source: String, dest: String)?
        let fm = FileManager.default
        for path in paths {
            var srcDir: ObjCBool = false
            let isSrcFolder = fm.fileExists(atPath: path, isDirectory: &srcDir) && srcDir.boolValue
            let name = URL(fileURLWithPath: path).lastPathComponent
            let existing = URL(fileURLWithPath: dest).appendingPathComponent(name).path
            var dstDir: ObjCBool = false
            let hasSameFolder = fm.fileExists(atPath: existing, isDirectory: &dstDir) && dstDir.boolValue
            if isSrcFolder, hasSameFolder,
               (path as NSString).standardizingPath != (existing as NSString).standardizingPath {
                if firstMerge == nil {
                    firstMerge = (path, existing)
                } else {
                    remaining.append(path)
                }
            } else {
                remaining.append(path)
            }
        }
        if let merge = firstMerge {
            pendingMergeMove = move
            pendingMergePreview = FolderMerge.preview(source: merge.source, dest: merge.dest)
            statusMessage = "Revisa la fusión antes de tocar el destino"
        }
        return remaining
    }

    func appendAgentUser(_ text: String) {
        agentMessages.append(AgentChatMessage(role: .user, text: text))
        trimAgentChat()
    }

    /// Respuesta visible en el panel + franja grande abajo.
    func appendAgentReply(_ text: String, alsoStatus: Bool = true) {
        agentMessages.append(AgentChatMessage(role: .assistant, text: text))
        agentLog.append(text)
        trimAgentChat()
        if alsoStatus {
            statusMessage = text
        }
    }

    func clearAgentChat() {
        agentMessages = []
        agentLog = []
    }

    private func trimAgentChat() {
        if agentMessages.count > 60 {
            agentMessages = Array(agentMessages.suffix(40))
        }
        if agentLog.count > 80 {
            agentLog = Array(agentLog.suffix(60))
        }
    }

    /// Botón Actualizar / refrescar a mano: avisa en grande.
    func reloadFromUser() {
        reload()
        let n = visibleEntries.count
        let msg = n == 1
            ? "Listo: actualicé esta carpeta. Hay 1 elemento."
            : "Listo: actualicé esta carpeta. Hay \(n) elementos."
        appendAgentReply(msg)
        showAssistantPanel = true
    }

    func runAssistant(prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showAssistantPanel = true
        appendAgentUser(trimmed)
        agentLog.append("> \(trimmed)")

        if let shortcut = matchAssistantShortcut(prompt: trimmed) {
            applyAssistantShortcut(shortcut)
            return
        }

        if let llm = await OllamaClient.shared.proposePlan(prompt: trimmed, currentPath: currentPath) {
            agentPlan = llm
            agentLog.append("Plan (Ollama): \(llm.summary)")
        } else {
            let plan = AgentIntentParser.plan(from: trimmed, currentPath: currentPath)
            agentPlan = plan
            agentLog.append("Plan (reglas): \(plan.summary)")
        }
        // Fase 2–3: solo lectura se ejecuta solo. Escritura espera aprobación (fase 5).
        if let plan = agentPlan, !plan.needsApproval {
            executeAgentPlan(approved: true)
        } else if let plan = agentPlan, plan.needsApproval {
            pendingAgentApproval = plan
            appendAgentReply(
                "Esto va a modificar archivos. Revisa el plan y dale a Aprobar si estás de acuerdo.",
                alsoStatus: true
            )
        }
    }

    func executeAgentPlan(approved: Bool) {
        guard let plan = agentPlan else { return }
        if plan.needsApproval, !approved {
            pendingAgentApproval = plan
            appendAgentReply("Esperando tu aprobación para seguir.", alsoStatus: true)
            return
        }
        for step in plan.steps {
            switch step.name {
            case .searchFiles:
                let q = step.arguments["query"] ?? plan.prompt
                startDeepSearch(query: q)
                appendAgentReply(
                    "Busco archivos cuyo nombre coincida con «\(q)» en esta carpeta y subcarpetas. Mira la lista o el filtro de búsqueda."
                )
            case .searchContent:
                let q = step.arguments["query"] ?? plan.prompt
                startDeepSearch(query: q)
                appendAgentReply(
                    "Por ahora busco por nombre «\(q)» (aún no leo el contenido con IA; eso es fase 3)."
                )
            case .listDirectory:
                reload()
                let n = visibleEntries.count
                appendAgentReply(
                    n == 0
                        ? "Esta carpeta está vacía (o no pude listar nada)."
                        : "Aquí hay \(n) elementos. La lista del centro está al día."
                )
            case .getStorageUsage:
                showHeaviestForCleanup()
                appendAgentReply(
                    "Ordené por peso: lo más pesado arriba. Arriba del todo verás el Top peso con los que más ocupan."
                )
            case .findDuplicates:
                let dups = findDuplicateCandidates()
                if dups == 0 {
                    appendAgentReply(
                        "No encontré duplicados obvios aquí (mismo nombre y mismo tamaño). Si hay copias con otro nombre, aún no las detecto."
                    )
                } else {
                    appendAgentReply(
                        dups == 1
                            ? "Encontré 1 grupo posible de duplicados y lo marqué en la lista."
                            : "Encontré \(dups) grupos posibles de duplicados. Marqué el primero en la lista."
                    )
                }
            case .organizeFiles:
                appendAgentReply(
                    "Organizar archivos (mover/crear carpetas) llega en la fase 5, con tu visto bueno antes de tocar nada."
                )
            case .openFile:
                if let p = step.arguments["path"], let entry = entries.first(where: { $0.path == p }) {
                    open(entry)
                    appendAgentReply("Abrí «\(entry.name)».")
                } else {
                    appendAgentReply("No pude abrir ese archivo: no está en la carpeta actual.")
                }
            case .previewFile:
                quickLookSelection()
                appendAgentReply("Abrí Vista rápida de la selección.")
            case .getFileMetadata:
                if let p = step.arguments["path"], let entry = entries.first(where: { $0.path == p }) {
                    showInfo(entry)
                    appendAgentReply("Mostré la info de «\(entry.name)».")
                } else if let entry = selectedEntries.first {
                    showInfo(entry)
                    appendAgentReply("Mostré la info de la selección.")
                } else {
                    appendAgentReply("No hay nada seleccionado para mostrar info.")
                }
            case .createDirectory, .copyFiles, .moveFiles, .renameFiles:
                appendAgentReply(
                    "Esa acción escribe o mueve archivos. Todavía no la ejecuto sola: llega en la fase 5 con aprobación."
                )
            }
        }
        if !plan.needsApproval || approved {
            agentPlan = nil
            pendingAgentApproval = nil
        }
    }

    /// Duplicados simples por nombre+tamaño en la carpeta actual (no recursivo aún).
    @discardableResult
    func findDuplicateCandidates() -> Int {
        var buckets: [String: [FileEntry]] = [:]
        for e in entries where !e.isDirectory {
            let key = "\(e.name.lowercased())|\(e.size)"
            buckets[key, default: []].append(e)
        }
        let groups = buckets.values.filter { $0.count > 1 }
        if let first = groups.first {
            selectedIDs = Set(first.map(\.id))
            selectionAnchorID = first.first?.id
            refreshSelectionStatus()
        }
        statusMessage = groups.isEmpty
            ? "Sin duplicados obvios aquí"
            : "\(groups.count) grupos posibles (nombre+tamaño)"
        return groups.count
    }

    func setExplorerKeyboardProfile(_ on: Bool) {
        explorerKeyboardProfile = on
        store.update { $0.explorerKeyboardProfile = on }
    }

    /// Como Alt+← en Windows / ⌘[ en Finder.
    /// Sin historial (p. ej. abriste directo en una subcarpeta): sube al padre.
    func goBack() {
        if let previous = backStack.popLast() {
            forwardStack.append(currentPath)
            navigate(to: previous, recordHistory: false)
            statusMessage = "Atrás"
            refreshHistoryFlags()
            return
        }
        if canNavigateUp {
            goUp()
            statusMessage = "Atrás · carpeta superior"
            return
        }
        statusMessage = "No hay carpeta anterior"
        refreshHistoryFlags()
    }

    /// Como Alt+→ en Windows / ⌘] en Finder.
    func goForward() {
        guard let next = forwardStack.popLast() else {
            statusMessage = "No hay carpeta siguiente"
            refreshHistoryFlags()
            return
        }
        backStack.append(currentPath)
        navigate(to: next, recordHistory: false)
        statusMessage = "Adelante"
        refreshHistoryFlags()
    }

    func goUp() {
        guard let parent = parentPath(of: currentPath) else { return }
        navigate(to: parent)
    }

    private var canNavigateUp: Bool {
        parentPath(of: currentPath) != nil
    }

    private func parentPath(of path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        let current = (path as NSString).standardizingPath
        let standardizedParent = (parent as NSString).standardizingPath
        guard !parent.isEmpty, standardizedParent != current else { return nil }
        return standardizedParent
    }

    private func pushHistoryBeforeLeavingCurrent() {
        let current = (currentPath as NSString).standardizingPath
        if backStack.last != current {
            backStack.append(current)
            // Evitar historial infinito
            if backStack.count > 80 {
                backStack.removeFirst(backStack.count - 80)
            }
        }
        forwardStack.removeAll()
        refreshHistoryFlags()
    }

    private func refreshHistoryFlags() {
        canGoBack = !backStack.isEmpty || canNavigateUp
        canGoForward = !forwardStack.isEmpty
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
        downloadsTodayMode = false
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
        downloadsTodayMode = false
        cleanupMode = false
        applyRule(.downloads, scope: .everywhere)
        rule = .downloads
    }

    func useGlobalDefaultHere() {
        downloadsTodayMode = false
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

    /// Orden por peso: lo más pesado arriba (no borra nada).
    func showHeaviestForCleanup() {
        downloadsTodayMode = false
        activeAssistantShortcut = nil
        cleanupMode = true
        rule = .heaviestFirst
        let msg = "Listo: ordené por peso. Arriba está lo que más ocupa. No borré nada."
        appendAgentReply(msg)
        objectWillChange.send()
    }

    func exitCleanupMode() {
        cleanupMode = false
        rule = store.preferences.rule(for: currentPath)
        appendAgentReply("Volviste al orden normal de esta carpeta.")
        objectWillChange.send()
    }

    /// Modo exclusivo: solo lo agregado/creado hoy en la carpeta actual.
    func toggleDownloadsTodayMode() {
        if downloadsTodayMode {
            exitDownloadsTodayMode()
            return
        }
        cleanupMode = false
        activeAssistantShortcut = nil
        downloadsTodayMode = true
        clearSelection()
        let n = downloadsTodayCount
        statusMessage = n == 0
            ? "Modo Descargados: no hay nada de hoy aquí"
            : "Modo Descargados: \(n) de hoy (el resto oculto)"
        objectWillChange.send()
    }

    func exitDownloadsTodayMode() {
        downloadsTodayMode = false
        statusMessage = "Saliste del modo Descargados"
        objectWillChange.send()
    }

    // MARK: Atajos del asistente

    func applyAssistantShortcut(_ shortcut: AssistantShortcut) {
        downloadsTodayMode = false
        cleanupMode = false
        categoryFilter = nil
        activeAssistantShortcut = shortcut
        clearSelection()
        showAssistantPanel = true
        let n = visibleEntries.count
        let msg: String
        if n == 0 {
            msg = "Atajo «\(shortcut.title)»: no hay nada que coincida en esta carpeta."
        } else if n == 1 {
            msg = "Atajo «\(shortcut.title)»: 1 archivo. Lo más nuevo arriba."
        } else {
            msg = "Atajo «\(shortcut.title)»: \(n) archivos. Lo más nuevo arriba."
        }
        appendAgentReply(msg)
        objectWillChange.send()
    }

    func clearAssistantShortcutFilter() {
        guard activeAssistantShortcut != nil else { return }
        activeAssistantShortcut = nil
        appendAgentReply("Quité el filtro del atajo. Otra vez ves toda la carpeta.")
        objectWillChange.send()
    }

    @discardableResult
    func addAssistantShortcut(_ shortcut: AssistantShortcut) -> String? {
        if assistantShortcuts.count >= AssistantShortcut.maxCount {
            return "Ya tienes \(AssistantShortcut.maxCount) atajos (tope). Borra alguno para crear otro."
        }
        var next = shortcut
        if next.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.title = defaultTitle(for: next)
        }
        assistantShortcuts.insert(next, at: 0)
        persistAssistantShortcuts()
        appendAgentReply("Guardé el atajo «\(next.title)». Queda fijo aquí para reusarlo.")
        return nil
    }

    func deleteAssistantShortcut(id: UUID) {
        assistantShortcuts.removeAll { $0.id == id }
        if activeAssistantShortcut?.id == id {
            activeAssistantShortcut = nil
        }
        persistAssistantShortcuts()
    }

    func updateAssistantShortcut(_ shortcut: AssistantShortcut) {
        guard let idx = assistantShortcuts.firstIndex(where: { $0.id == shortcut.id }) else {
            _ = addAssistantShortcut(shortcut)
            return
        }
        var next = shortcut
        if next.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.title = defaultTitle(for: next)
        }
        assistantShortcuts[idx] = next
        if activeAssistantShortcut?.id == next.id {
            activeAssistantShortcut = next
        }
        persistAssistantShortcuts()
    }

    func moveAssistantShortcut(from source: IndexSet, to destination: Int) {
        assistantShortcuts.move(fromOffsets: source, toOffset: destination)
        persistAssistantShortcuts()
    }

    func restoreDefaultAssistantShortcuts() {
        assistantShortcuts = AssistantShortcut.factoryDefaults()
        activeAssistantShortcut = nil
        persistAssistantShortcuts()
        appendAgentReply("Restauré los atajos de fábrica (\(assistantShortcuts.count)).")
    }

    func persistAssistantShortcuts() {
        let capped = Array(assistantShortcuts.prefix(AssistantShortcut.maxCount))
        assistantShortcuts = capped
        store.update { $0.assistantShortcuts = capped }
    }

    func setOllamaEnabled(_ on: Bool) {
        store.update { $0.ollamaEnabled = on }
        OllamaClient.shared.applyPreferences(store.preferences)
        Task { await OllamaClient.shared.refresh() }
    }

    func setOllamaModel(_ model: String) {
        store.update { $0.ollamaModel = model }
        OllamaClient.shared.applyPreferences(store.preferences)
    }

    private func defaultTitle(for shortcut: AssistantShortcut) -> String {
        let typePart: String
        if shortcut.categories == AssistantShortcut.documentCategories {
            typePart = "Documentos"
        } else if shortcut.categories.count == 1, let only = shortcut.categories.first {
            typePart = only.labelSpanish + "s"
        } else if shortcut.categories.isEmpty {
            typePart = "Archivos"
        } else {
            typePart = "Varios"
        }
        return "\(typePart) \(shortcut.dateWindow.labelSpanish)"
    }

    /// Si el texto coincide con un atajo guardado o una frase tipo+fecha, lo aplica.
    func matchAssistantShortcut(prompt: String) -> AssistantShortcut? {
        let lower = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let saved = assistantShortcuts.first(where: { $0.title.lowercased() == lower }) {
            return saved
        }
        return AgentIntentParser.inferShortcut(from: lower)
    }

    func open(_ entry: FileEntry) {
        if entry.isDirectory {
            navigate(to: entry.path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        }
    }

    /// Apps que macOS asocia a este archivo (como Finder → Abrir con).
    func appsForOpening(_ entry: FileEntry) -> [OpenWithApp] {
        guard !entry.isDirectory else { return [] }
        let fileURL = URL(fileURLWithPath: entry.path)
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        var seen = Set<String>()
        var result: [OpenWithApp] = []
        for appURL in apps {
            let path = appURL.path
            guard seen.insert(path).inserted else { continue }
            let name = FileManager.default.displayName(atPath: path)
            result.append(OpenWithApp(id: path, name: name, url: appURL))
            if result.count >= 15 { break }
        }
        return result
    }

    func open(_ entry: FileEntry, withApplicationAt appURL: URL) {
        guard !entry.isDirectory else {
            navigate(to: entry.path)
            return
        }
        let fileURL = URL(fileURLWithPath: entry.path)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config) { _, error in
            if let error {
                Task { @MainActor in
                    self.statusMessage = "No se pudo abrir: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Cambia la app por defecto para este tipo (como «Cambiar todo…» del Finder).
    func setDefaultApplication(_ appURL: URL, for entry: FileEntry) {
        guard !entry.isDirectory else { return }
        let fileURL = URL(fileURLWithPath: entry.path)
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenContentTypeOfFileAt: fileURL) { error in
            Task { @MainActor in
                if let error {
                    self.statusMessage = "No se pudo cambiar la app: \(error.localizedDescription)"
                } else {
                    let name = FileManager.default.displayName(atPath: appURL.path)
                    self.statusMessage = "Ahora \(entry.name) y similares se abren con \(name)"
                }
            }
        }
    }

    func showInfo(_ entry: FileEntry) {
        FileInfoPanel.show(entry)
    }

    func compressSelection() {
        let targets = selectedEntries.isEmpty ? [] : selectedEntries
        let paths = targets.map(\.path)
        guard !paths.isEmpty else {
            statusMessage = "Selecciona algo para comprimir"
            return
        }
        let destName: String = {
            if paths.count == 1 {
                let base = URL(fileURLWithPath: paths[0]).deletingPathExtension().lastPathComponent
                return "\(base).zip"
            }
            return "Archivo.zip"
        }()
        var dest = (currentPath as NSString).appendingPathComponent(destName)
        var n = 2
        while FileManager.default.fileExists(atPath: dest) {
            let stem = URL(fileURLWithPath: destName).deletingPathExtension().lastPathComponent
            dest = (currentPath as NSString).appendingPathComponent("\(stem) \(n).zip")
            n += 1
        }
        statusMessage = "Comprimiendo…"
        let folder = currentPath
        let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = URL(fileURLWithPath: folder)
            process.arguments = ["-r", dest] + names
            do {
                try process.run()
                process.waitUntilExit()
                let ok = process.terminationStatus == 0
                await MainActor.run {
                    if ok {
                        self.statusMessage = "Comprimido: \(URL(fileURLWithPath: dest).lastPathComponent)"
                        self.reload()
                    } else {
                        self.statusMessage = "No se pudo comprimir"
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "No se pudo comprimir: \(error.localizedDescription)"
                }
            }
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
        QuickLookController.shared.toggle(browser: self, focusing: paths)
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
        selectionFocusID = nil
        noteLocalFileMutation()
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
            noteLocalFileMutation()
            reload()
            selectOnly(path)
            statusMessage = "Carpeta creada: \(URL(fileURLWithPath: path).lastPathComponent)"
        } catch {
            statusMessage = "No se pudo crear: \(error.localizedDescription)"
        }
    }

    func promptNewFile() {
        nameDraft = "Sin título.txt"
        showNewFileDialog = true
    }

    func createFileFromDraft() {
        var name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        // Si no pone extensión, .txt por defecto (cositas de texto).
        if !name.contains(".") {
            name += ".txt"
        }
        do {
            let path = try FileOps.createFile(named: name, in: currentPath)
            noteLocalFileMutation()
            reload()
            selectOnly(path)
            statusMessage = "Archivo creado: \(URL(fileURLWithPath: path).lastPathComponent)"
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
            noteLocalFileMutation()
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
                noteLocalFileMutation()
                reload()
                return
            }
        }
        noteLocalFileMutation()
        reload()
        if let lastPath {
            selectOnly(lastPath)
        }
        statusMessage = count == 1 ? "Duplicado" : "\(count) duplicados"
    }

    /// Paths que se armarían si haces hold sobre `entry` (selección múltiple incluida).
    func dragArmGroup(for entry: FileEntry) -> [String] {
        if selectedIDs.contains(entry.id), selectedIDs.count > 1 {
            return selectedEntries.map(\.path)
        }
        return [entry.path]
    }

    /// Empieza el anillo de progreso al pulsar (antes de los 1s).
    func beginArmingFileDrag(for entry: FileEntry) {
        // Si ya estamos armando este gesto, no reinicies el anillo.
        if fileDragArmingPrimaryPath == entry.path, armingProgressTask != nil { return }
        if isFileDragArmed(path: entry.path) { return }

        armingProgressTask?.cancel()
        let group = dragArmGroup(for: entry)
        fileDragArmingPaths = Set(group)
        fileDragArmingPrimaryPath = entry.path
        fileDragArmProgress = 0
        let path = entry.path
        let entryCopy = entry
        let steps = 20
        let stepNanos: UInt64 = 50_000_000 // 20 × 50ms = 1s
        armingProgressTask = Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: stepNanos)
                guard !Task.isCancelled, self.fileDragArmingPrimaryPath == path else { return }
                self.fileDragArmProgress = Double(i) / Double(steps)
            }
            guard !Task.isCancelled, self.fileDragArmingPrimaryPath == path else { return }
            // Hold completo sin soltar → arma aunque el mouse no se haya movido.
            self.armFileDrag(for: entryCopy)
        }
    }

    /// Soltaste antes de armar → quita el anillo (no toca el estado armado).
    func endArmingPress(for entry: FileEntry) {
        armingProgressTask?.cancel()
        armingProgressTask = nil
        if fileDragArmingPrimaryPath == entry.path {
            fileDragArmingPaths = []
            fileDragArmingPrimaryPath = nil
            fileDragArmProgress = 0
        }
    }

    /// Compat: hold antiguo / llamadas internas → mismo efecto que ⌘+clic (rango + naranja).
    func armFileDrag(for entry: FileEntry) {
        commandRangeSelectForMove(to: entry.id)
    }

    func isFileDragArmed(path: String) -> Bool {
        hasArmedFileDrag && fileDragArmedPaths.contains(path)
    }

    var hasArmedFileDrag: Bool {
        !fileDragArmedPaths.isEmpty
    }

    /// Paths armados sin apagar el naranja (el drag puede fallar / cancelarse).
    func peekArmedFileDrag() -> [String] {
        hasArmedFileDrag ? fileDragArmedPaths : []
    }

    /// Compat: ya no apaga el modo; usa `peekArmedFileDrag`.
    func consumeArmedFileDrag() -> [String] {
        peekArmedFileDrag()
    }

    /// Arrastre nativo sin apagar el naranja; solo se apaga si el drop tuvo éxito.
    @discardableResult
    func startArmedNativeDrag() -> Bool {
        let paths = peekArmedFileDrag()
        guard !paths.isEmpty else { return false }
        FolderDragBridge.shared.onSessionEnded = { [weak self] dropped in
            guard let self, dropped else { return }
            self.clearArmedFileDrag()
            self.reload()
        }
        return FolderDragBridge.shared.startDrag(paths: paths)
    }

    func clearArmedFileDrag() {
        armingProgressTask?.cancel()
        armingProgressTask = nil
        fileDragArmedPaths = []
        fileDragArmingPaths = []
        fileDragArmingPrimaryPath = nil
        fileDragArmProgress = 0
    }

    /// ⌘C → a la bandeja como copia.
    func copySelectionToPasteboard() {
        addSelectionToShelf(intent: .copy)
    }

    /// ⌘X → a la bandeja como mover.
    func cutSelectionToPasteboard() {
        addSelectionToShelf(intent: .move)
    }

    /// ⌘V → suelta la bandeja aquí (cada ítem según su intención).
    func pasteFromPasteboard() {
        if !shelf.isEmpty {
            depositShelfHere()
            return
        }
        // Fallback: portapapeles del sistema (Finder, etc.)
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            statusMessage = "Bandeja y portapapeles vacíos"
            return
        }
        let paths = urls.map(\.path)
        let rest = offerMergeIfNeeded(paths: paths, toDirectory: currentPath, move: false)
        guard !rest.isEmpty else { return }
        do {
            let pairs = try FileOps.transfer(paths: rest, toDirectory: currentPath, move: false)
            pushUndo(.copied(created: pairs.map(\.to)))
            noteLocalFileMutation()
            reload()
            statusMessage = pairs.count == 1 ? "1 archivo pegado" : "\(pairs.count) archivos pegados"
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

    func addSelectionToShelf(intent: FileOps.ShelfIntent = .move) {
        let entries = selectedEntries
        guard !entries.isEmpty else {
            statusMessage = "Selecciona algo para la bandeja"
            return
        }
        for entry in entries {
            upsertShelfItem(FileOps.ShelfItem(entry: entry, intent: intent))
        }
        let verb = intent == .move ? "para mover" : "para copiar"
        statusMessage = entries.count == 1
            ? "En bandeja \(verb) — ve abajo o ⌘V aquí"
            : "\(entries.count) en bandeja \(verb) — ⌘V suelta aquí"
        objectWillChange.send()
    }

    func addPathsToShelf(_ paths: [String], intent: FileOps.ShelfIntent = .move) {
        for path in paths {
            let name = URL(fileURLWithPath: path).lastPathComponent
            upsertShelfItem(FileOps.ShelfItem(path: path, name: name, intent: intent))
        }
        statusMessage = "Bandeja: \(shelf.count) ítem(s)"
    }

    private func upsertShelfItem(_ item: FileOps.ShelfItem) {
        if let idx = shelf.firstIndex(where: { $0.path == item.path }) {
            shelf[idx].intent = item.intent
        } else {
            shelf.append(item)
        }
    }

    func removeFromShelf(_ item: FileOps.ShelfItem) {
        shelf.removeAll { $0.path == item.path }
    }

    func clearShelf() {
        shelf.removeAll()
        statusMessage = "Bandeja vacía"
    }

    func moveShelfHere() {
        transferShelf(forceMove: true)
    }

    func copyShelfHere() {
        transferShelf(forceMove: false)
    }

    /// Respeta la intención de cada ítem (⌘C copia / ⌘X mueve).
    func depositShelfHere() {
        guard !shelf.isEmpty else {
            statusMessage = "La bandeja está vacía"
            return
        }
        var movedPairs: [FileOps.TransferPair] = []
        var copiedPairs: [FileOps.TransferPair] = []
        var remaining: [FileOps.ShelfItem] = []
        do {
            for item in shelf {
                let move = item.intent == .move
                let rest = offerMergeIfNeeded(paths: [item.path], toDirectory: currentPath, move: move)
                if rest.isEmpty {
                    // Quedó en preview de fusión; no reponer en bandeja si era move hasta cancelar.
                    if !move { remaining.append(item) }
                    continue
                }
                let pairs = try FileOps.transfer(
                    paths: rest,
                    toDirectory: currentPath,
                    move: move
                )
                if move {
                    movedPairs.append(contentsOf: pairs)
                } else {
                    copiedPairs.append(contentsOf: pairs)
                    remaining.append(item)
                }
            }
            shelf = remaining
            if !movedPairs.isEmpty { pushUndo(.moved(pairs: movedPairs)) }
            if !copiedPairs.isEmpty { pushUndo(.copied(created: copiedPairs.map(\.to))) }
            if pendingMergePreview == nil {
                reload()
                var parts: [String] = []
                if !movedPairs.isEmpty { parts.append("\(movedPairs.count) movido(s)") }
                if !copiedPairs.isEmpty { parts.append("\(copiedPairs.count) copiado(s)") }
                statusMessage = parts.isEmpty ? "Nada transferido" : parts.joined(separator: " · ") + " · ⌘Z deshace"
            } else if !movedPairs.isEmpty || !copiedPairs.isEmpty {
                reload()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func transferShelf(forceMove: Bool) {
        let paths = shelf.map(\.path)
        guard !paths.isEmpty else {
            statusMessage = "La bandeja está vacía"
            return
        }
        let rest = offerMergeIfNeeded(paths: paths, toDirectory: currentPath, move: forceMove)
        guard !rest.isEmpty else { return }
        do {
            let pairs = try FileOps.transfer(paths: rest, toDirectory: currentPath, move: forceMove)
            if forceMove {
                shelf.removeAll { rest.contains($0.path) }
                pushUndo(.moved(pairs: pairs))
            } else {
                pushUndo(.copied(created: pairs.map(\.to)))
            }
            reload()
            statusMessage = forceMove
                ? "Movidos \(pairs.count) a esta carpeta · ⌘Z deshace"
                : "Copiados \(pairs.count) a esta carpeta · ⌘Z deshace"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Deshacer (⌘Z)

    private func pushUndo(_ record: UndoRecord) {
        undoStack.append(record)
        if undoStack.count > undoLimit {
            undoStack.removeFirst(undoStack.count - undoLimit)
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// ⌘Z — deshacer último movimiento/copia (como Explorer).
    func undoLastFileOp() {
        guard let record = undoStack.popLast() else {
            statusMessage = "Nada que deshacer"
            return
        }
        do {
            switch record {
            case .moved(let pairs):
                var restored = 0
                for pair in pairs.reversed() {
                    let current = URL(fileURLWithPath: pair.to)
                    guard FileManager.default.fileExists(atPath: current.path) else { continue }
                    let originalParent = URL(fileURLWithPath: pair.from).deletingLastPathComponent()
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: originalParent.path, isDirectory: &isDir),
                          isDir.boolValue else { continue }
                    var dest = URL(fileURLWithPath: pair.from)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        dest = FileOps.uniqueURL(dest)
                    }
                    try FileManager.default.moveItem(at: current, to: dest)
                    restored += 1
                }
                reload()
                statusMessage = restored == 0
                    ? "No se pudo deshacer el movimiento"
                    : "Deshecho: \(restored) movido(s) de vuelta"
            case .copied(let created):
                var trashed = 0
                for path in created.reversed() {
                    let url = URL(fileURLWithPath: path)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    trashed += 1
                }
                reload()
                statusMessage = trashed == 0
                    ? "No se pudo deshacer la copia"
                    : "Deshecho: \(trashed) copia(s) a la Papelera"
            }
        } catch {
            statusMessage = "No se pudo deshacer: \(error.localizedDescription)"
        }
    }

    /// Paths para arrastrar a Dropover / Finder / otras apps.
    func dragPaths(for entry: FileEntry) -> [String] {
        if selectedIDs.contains(entry.id), selectedIDs.count > 1 {
            return selectedEntries.map(\.path)
        }
        return [entry.path]
    }

    /// Rutas a sacar fuera de Ordena (selección, o bandeja si no hay selección).
    var outboundPaths: [String] {
        let selected = selectedEntries.map(\.path).filter {
            FileManager.default.fileExists(atPath: $0)
        }
        if !selected.isEmpty { return selected }
        return shelf.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Mete la selección (o bandeja) en una burbuja de Dropover para arrastrar a Terminal, Cursor, etc.
    func sendOutboundToDropover() {
        let paths = outboundPaths
        guard !paths.isEmpty else {
            statusMessage = "Selecciona archivos o lléná la bandeja"
            return
        }
        let dropoverURL: URL? =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "me.damir.dropover-mac")
            ?? {
                let fallback = URL(fileURLWithPath: "/Applications/Dropover.app", isDirectory: true)
                return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
            }()
        guard let dropoverURL else {
            statusMessage = "No encontré Dropover.app en /Applications"
            return
        }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: dropoverURL, configuration: config) { _, error in
            Task { @MainActor in
                if let error {
                    self.statusMessage = "Dropover: \(error.localizedDescription)"
                } else {
                    self.statusMessage = paths.count == 1
                        ? "En Dropover — arrástralo a Terminal o Cursor"
                        : "\(paths.count) en Dropover — arrástralos a otra app"
                }
            }
        }
    }

    /// Copia rutas POSIX entrecomilladas (útil en Terminal / pegar en Cursor).
    func copyOutboundPaths() {
        let paths = outboundPaths
        guard !paths.isEmpty else {
            statusMessage = "Nada seleccionado para copiar rutas"
            return
        }
        let quoted = paths.map { path -> String in
            if path.contains(" ") || path.contains("'") {
                let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
                return "'\(escaped)'"
            }
            return path
        }.joined(separator: " ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(quoted, forType: .string)
        statusMessage = paths.count == 1
            ? "Ruta copiada — ⌘V en Terminal o Cursor"
            : "\(paths.count) rutas copiadas"
    }

    func importDroppedFiles(providers: [NSItemProvider]) -> Bool {
        collectDroppedPaths(providers) { paths in
            self.addPathsToShelf(paths)
        }
        return true
    }

    /// Suelta archivos/carpetas DENTRO de una carpeta destino (no a la bandeja).
    /// ⌥ = copiar; sin ⌥ = mover.
    @discardableResult
    func handleDropIntoFolder(providers: [NSItemProvider], folderPath: String) -> Bool {
        collectDroppedPaths(providers) { paths in
            self.dropPaths(paths, intoFolder: folderPath)
        }
        return true
    }

    func dropPaths(_ paths: [String], intoFolder folderPath: String) {
        let dest = (folderPath as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dest, isDirectory: &isDir), isDir.boolValue else {
            statusMessage = "Ese destino no es una carpeta"
            return
        }

        let copy = NSEvent.modifierFlags.contains(.option)
        let unique = Array(Set(paths.map { ($0 as NSString).standardizingPath }))
            .filter { path in
                if path == dest { return false }
                // No meter una carpeta dentro de sí misma / descendiente
                if dest.hasPrefix(path + "/") { return false }
                return true
            }
        guard !unique.isEmpty else {
            statusMessage = "No se puede soltar ahí"
            return
        }

        let move = !copy
        let rest = offerMergeIfNeeded(paths: unique, toDirectory: dest, move: move)
        guard !rest.isEmpty else {
            folderDropTargetPath = nil
            clearArmedFileDrag()
            return
        }
        do {
            let pairs = try FileOps.transfer(paths: rest, toDirectory: dest, move: move)
            if copy {
                pushUndo(.copied(created: pairs.map(\.to)))
            } else {
                shelf.removeAll { rest.contains(($0.path as NSString).standardizingPath) }
                selectedIDs = []
                pushUndo(.moved(pairs: pairs))
            }
            folderDropTargetPath = nil
            clearArmedFileDrag()
            noteLocalFileMutation()
            reload()
            let name = URL(fileURLWithPath: dest).lastPathComponent
            statusMessage = copy
                ? "Copiados \(pairs.count) → \(name) · ⌘Z deshace"
                : "Movidos \(pairs.count) → \(name) · ⌘Z deshace"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func collectDroppedPaths(
        _ providers: [NSItemProvider],
        then: @escaping @MainActor ([String]) -> Void
    ) {
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
            then(collected)
        }
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

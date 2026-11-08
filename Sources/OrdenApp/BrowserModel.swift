import Foundation
import SwiftUI
import OrdenCore
import AppKit
import UniformTypeIdentifiers
import Combine

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
    @Published var sizeMeasurementsIncomplete = false
    @Published var cleanupMode = false
    /// Modo exclusivo: solo ítems agregados/creados hoy en esta carpeta (descargas del día).
    @Published var downloadsTodayMode = false
    /// Atajo del asistente activo (tipo + fechas).
    @Published var activeAssistantShortcut: AssistantShortcut? = nil
    @Published var assistantShortcuts: [AssistantShortcut] = []

    // MARK: Dual pane (dos carpetas lado a lado para mover)
    enum PaneFocus: String, Equatable {
        case primary
        case secondary
    }
    @Published var dualPaneEnabled = false
    @Published var focusedPane: PaneFocus = .primary
    @Published var secondaryPath: String = ""
    @Published var secondaryEntries: [FileEntry] = []
    @Published var secondarySelectedIDs: Set<String> = []
    /// Ancla / cursor de selección del panel Destino (⇧ / flechas).
    @Published var secondarySelectionAnchorID: String?
    @Published var secondarySelectionFocusID: String?
    @Published var secondaryError: String?
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
        /// Smart Merge: elimina las copias nuevas y restaura respaldos/origen desde la Papelera.
        case merged(
            created: [String],
            sourceOriginalPath: String?,
            sourceTrashPath: String?,
            replacements: [FolderMerge.Replacement]
        )
    }
    /// Clic simple agrega/quita sin ⌘ (ideal para marcar muchos rápido).
    @Published var multiSelectMode = false
    /// Ancla para ⇧ clic / ⇧ flechas (rango). No se mueve al extender.
    @Published var selectionAnchorID: String?
    /// Tras ⌘+clic del monitor AppKit, ignorar el clic SwiftUI que llega sin modificadores y te deja 1 solo.
    private var ignorePlainSelectUntil: Date?
    /// Cursor de teclado: fila activa al navegar con flechas (con o sin ⇧).
    @Published var selectionFocusID: String?
    /// Pedido de scroll hasta un ítem (p. ej. al clic en resultado de búsqueda).
    @Published var revealEntryID: String?
    @Published var revealToken: Int = 0
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
    /// Mostrar ocultos (⌘⇧.).
    @Published var showHiddenFiles: Bool
    /// Vista plana de archivos bajo la carpeta.
    @Published var flattenFolderView: Bool
    /// Omnibox: editar ruta en la barra de breadcrumbs.
    @Published var pathOmniboxEditing = false
    @Published var pathOmniboxDraft = ""
    /// Progreso de TransferQueue (barra de estado).
    @Published var transferProgressFraction: Double?
    @Published var transferProgressLabel: String?
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

    // MARK: Plantillas de vista
    @Published var viewTemplates: [ViewTemplate] = []
    @Published var showSaveTemplateDialog = false
    @Published var templateNameDraft = ""
    @Published var activeViewTemplateID: UUID?

    func runFolderHandlerSetup() {
        let result = OpenFolderBridge.prepareFolderOpener()
        folderHandlerSetupResult = result
        showFolderHandlerSetupDialog = true
        switch result {
        case .alreadyDefault:
            statusMessage = "Findaro ya está como app de carpetas"
        case .readyForOpenWith:
            statusMessage = "Findaro lista en «Abrir con» — falta elegir Siempre (límite de Apple)"
        case .appMissing:
            statusMessage = "No encuentro Findaro.app en Aplicaciones"
        }
    }
    @Published var agentLog: [String] = []
    /// Conversación legible (no terminal en miniatura).
    @Published var agentMessages: [AgentChatMessage] = []
    @Published var pendingAgentApproval: AgentPlan?
    /// true mientras el asistente espera a Ollama / ejecuta.
    @Published var agentBusy = false
    /// Texto fijo de progreso (banner), no se pierde en el chat.
    @Published var agentProgressLabel: String = ""

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
    private var prefsCancellable: AnyCancellable?
    private var measureTask: Task<Void, Never>?
    private let folderWatcher = FolderWatcher()
    private let secondaryFolderWatcher = FolderWatcher()

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
        let startRule = store.preferences.rule(for: start)
        self.rule = startRule
        self.cleanupMode = (startRule == .heaviestFirst)
        self.viewMode = store.preferences.viewMode
        self.showRowPaths = store.preferences.showRowPaths
        self.explorerKeyboardProfile = store.preferences.explorerKeyboardProfile
        self.showHiddenFiles = store.preferences.showHiddenFiles
        self.flattenFolderView = store.preferences.flattenFolderView
        self.assistantShortcuts = store.preferences.assistantShortcuts
        self.viewTemplates = store.preferences.viewTemplates
        self.columnPaths = [start]
        let desktop = (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent("Desktop")
        self.secondaryPath = FileManager.default.fileExists(atPath: desktop) ? desktop : start
        OllamaClient.shared.applyPreferences(store.preferences)
        folderWatcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.handleFolderWatcherEvent()
            }
        }
        secondaryFolderWatcher.onChange = { [weak self] in
            Task { @MainActor in
                self?.handleSecondaryFolderWatcherEvent()
            }
        }
        reload()
        reloadSecondary()
        refreshHistoryFlags()
        startWatchingCurrentFolder()

        prefsCancellable = NotificationCenter.default
            .publisher(for: PreferencesStore.preferencesDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.handlePreferencesDidChange(note)
            }
    }

    private func handlePreferencesDidChange(_ note: Notification) {
        if let sender = note.object as? PreferencesStore, sender === self.store {
            return
        }
        self.store.reloadFromDisk()
        let prefs = self.store.preferences
        self.assistantShortcuts = prefs.assistantShortcuts
        self.viewTemplates = prefs.viewTemplates
        self.showRowPaths = prefs.showRowPaths
        self.explorerKeyboardProfile = prefs.explorerKeyboardProfile
        self.showHiddenFiles = prefs.showHiddenFiles
        self.flattenFolderView = prefs.flattenFolderView
        self.viewMode = prefs.viewMode
        if !prefs.folderOverrides.keys.contains(currentPath) {
            self.rule = prefs.globalRule
        }
        OllamaClient.shared.applyPreferences(prefs)
        objectWillChange.send()
        reload()
        if dualPaneEnabled { reloadSecondary() }
    }

    /// Hay algún filtro / modo que oculta o reordena distinto al “normal”.
    var hasActiveViewFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || categoryFilter != nil
            || downloadsTodayMode
            || cleanupMode
            || activeAssistantShortcut != nil
            || showDeepSearchPanel
    }

    /// Vuelve al listado completo con el orden de la carpeta (sin chips ni búsqueda).
    func resetToNormalView() {
        if showDeepSearchPanel || deepSearchRunning {
            clearDeepSearch()
        }
        searchText = ""
        categoryFilter = nil
        if downloadsTodayMode {
            downloadsTodayMode = false
        }
        if cleanupMode {
            exitCleanupMode()
            return
        }
        if activeAssistantShortcut != nil {
            activeAssistantShortcut = nil
        }
        statusMessage = "Orden normal de la carpeta"
        objectWillChange.send()
    }

    private func canonicalFolderPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func sameFolder(_ lhs: String, _ rhs: String) -> Bool {
        canonicalFolderPath(lhs) == canonicalFolderPath(rhs)
    }

    private func handleFolderWatcherEvent() {
        let before = Set(entries.map(\.id))
        reload(preserveSelection: true, fromWatcher: true)
        let after = Set(entries.map(\.id))
        if before != after {
            statusMessage = "Carpeta actualizada"
        }
    }

    private func handleSecondaryFolderWatcherEvent() {
        guard dualPaneEnabled else { return }
        // Misma carpeta: el watcher primario ya refresca ambos paneles.
        guard !sameFolder(currentPath, secondaryPath) else { return }
        let before = Set(secondaryEntries.map(\.id))
        reloadSecondary(preserveSelection: true, fromWatcher: true)
        let after = Set(secondaryEntries.map(\.id))
        if before != after {
            statusMessage = "Panel destino actualizado"
        }
    }

    private func startWatchingCurrentFolder() {
        folderWatcher.watch(path: currentPath)
        startWatchingSecondaryFolder()
    }

    private func startWatchingSecondaryFolder() {
        guard dualPaneEnabled, !secondaryPath.isEmpty,
              !sameFolder(currentPath, secondaryPath) else {
            secondaryFolderWatcher.stop()
            return
        }
        secondaryFolderWatcher.watch(path: secondaryPath)
    }

    func reload(preserveSelection: Bool = false, fromWatcher: Bool = false) {
        // Inicia FSEvents ANTES de leer el directorio para no perder una descarga
        // que termine justo entre la lectura y el alta del observador.
        if !fromWatcher {
            startWatchingCurrentFolder()
        }

        let previous = preserveSelection ? selectedIDs : []
        let prevFocus = selectionFocusID
        let prevAnchor = selectionAnchorID
        // En refrescos FSEvents reutilizamos tamaños de carpeta ya medidos para
        // no relanzar walks caros ni provocar parpadeos durante descargas.
        let previousDirectorySizes = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry -> (String, Int64)? in
                guard entry.isDirectory, entry.size > 0 else { return nil }
                return (entry.path, entry.size)
            }
        )
        measureTask?.cancel()
        do {
            let loaded = try loadEntries(at: currentPath)
            var nextEntries = SortEngine.sort(loaded, by: rule)
            if fromWatcher, !previousDirectorySizes.isEmpty {
                nextEntries = nextEntries.map { entry in
                    guard entry.isDirectory,
                          let known = previousDirectorySizes[entry.path] else { return entry }
                    return FileEntry(
                        path: entry.path,
                        name: entry.name,
                        isDirectory: entry.isDirectory,
                        size: known,
                        dateModified: entry.dateModified,
                        dateCreated: entry.dateCreated,
                        dateAdded: entry.dateAdded,
                        kind: entry.kind
                    )
                }
            }
            entries = nextEntries
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
            folderTotalBytes = entries.reduce(Int64(0)) { $0 + $1.size }
            // FSEvents: reutilizar tamaños conocidos evita parpadeo, pero siempre
            // recalculamos en background para no dejar carpetas obsoletas.
            startMeasuringSizes()
        } catch {
            entries = []
            folderTotalBytes = 0
            errorMessage = error.localizedDescription
        }

        // Si ambos paneles muestran la misma carpeta, el evento del panel principal
        // también debe actualizar la lista secundaria (un solo FSEvents, dos listas).
        if dualPaneEnabled, sameFolder(currentPath, secondaryPath) {
            reloadSecondary(preserveSelection: true, fromWatcher: true)
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

    /// Clic: ⇧ rango · ⌘ suma/quita toggle · Varios/casilla · normal = uno.
    func clickSelect(_ id: String) {
        if dualPaneEnabled {
            focusedPane = .primary
        }
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            selectRange(to: id)
            if hasArmedFileDrag { syncArmedWithSelection() }
        } else if flags.contains(.command) {
            commandToggleSelect(to: id)
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

    /// ⌘+clic nativo de macOS: añade o quita el elemento individual sin alterar los demás.
    func commandToggleSelect(to id: String, pane: PaneFocus? = nil) {
        noteCommandClickHandled()
        let target = pane ?? (dualPaneEnabled ? focusedPane : .primary)
        if dualPaneEnabled, target == .secondary {
            focusedPane = .secondary
            toggleSecondarySelection(id)
            if hasArmedFileDrag {
                fileDragArmedPaths = secondarySelectedEntries.map(\.path)
            }
            return
        }
        if dualPaneEnabled { focusedPane = .primary }
        toggleSelection(id)
        if hasArmedFileDrag {
            fileDragArmedPaths = selectedEntries.map(\.path)
        }
    }

    /// Selección de rango para mover (conservada por compatibilidad).
    func commandRangeSelectForMove(to id: String, pane: PaneFocus? = nil) {
        noteCommandClickHandled()
        let target = pane ?? (dualPaneEnabled ? focusedPane : .primary)
        if dualPaneEnabled, target == .secondary {
            focusedPane = .secondary
            if secondarySelectionAnchorID == nil {
                secondarySelectionAnchorID = secondarySelectedIDs.first ?? id
            }
            selectSecondaryRange(to: id)
            armingProgressTask?.cancel()
            armingProgressTask = nil
            fileDragArmingPaths = []
            fileDragArmingPrimaryPath = nil
            fileDragArmProgress = 1
            fileDragArmedPaths = secondarySelectedEntries.map(\.path)
            statusMessage = fileDragArmedPaths.count <= 1
                ? "Destino listo para mover — ⌘+clic / arrastra a Origen · Esc cancela"
                : "Destino · \(fileDragArmedPaths.count) listos — arrastra a Origen · Esc"
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            objectWillChange.send()
            return
        }
        if dualPaneEnabled { focusedPane = .primary }
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

    func paneForPath(_ path: String) -> PaneFocus {
        let inPrimary = visibleEntries.contains { $0.path == path }
        let inSecondary = secondaryEntries.contains { $0.path == path }
        if dualPaneEnabled, focusedPane == .secondary, inSecondary { return .secondary }
        if inPrimary { return .primary }
        if inSecondary { return .secondary }
        return focusedPane
    }

    func activateEntry(_ entry: FileEntry) {
        clearArmedFileDrag()
        if entry.isDirectory {
            navigate(to: entry.path)
            statusMessage = "Abrí carpeta: \(entry.name)"
        } else if ArchiveOps.isExtractable(entry.path) {
            // open() pone el estado (descomprimiendo / listo); no pisar con «Abrí:».
            open(entry)
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
            base = matched
        } else if downloadsTodayMode {
            // Exclusivo: oculta todo lo que no sea actividad de hoy
            base = entries.filter { DownloadDayFilter.isActivityToday($0) }
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
        let needles = Self.filterNeedles(from: searchText)
        let filtered: [FileEntry]
        if needles.isEmpty {
            filtered = typed
        } else {
            filtered = typed.filter { entry in
                needles.contains { needle in
                    entry.name.localizedCaseInsensitiveContains(needle)
                        || entry.path.localizedCaseInsensitiveContains(needle)
                }
            }
        }
        // Cualquier filtro → lo más nuevo (Agregado) arriba.
        if isFilterSortingNewestFirst {
            return DownloadDayFilter.sortNewestFirst(filtered)
        }
        return filtered
    }

    /// Descarga hoy, tipo, búsqueda o atajo del asistente.
    private var isFilterSortingNewestFirst: Bool {
        downloadsTodayMode
            || categoryFilter != nil
            || activeAssistantShortcut != nil
            || !Self.filterNeedles(from: searchText).isEmpty
    }

    /// `*.png` → `.png` (comodines como en Finder no son regex; se ignoran `*` y `?`).
    static func filterNeedles(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let stripped = trimmed
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { return [trimmed] }
        return [stripped]
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

    /// Panel Destino enfocado (acciones de teclado / barra van ahí).
    var activeIsSecondary: Bool {
        dualPaneEnabled && focusedPane == .secondary
    }

    /// Carpeta del panel activo (Origen o Destino).
    var activeWorkingPath: String {
        activeIsSecondary ? secondaryPath : currentPath
    }

    /// ¿El panel Origen muestra la Papelera?
    var isViewingTrash: Bool {
        TrashOps.isTrashPath(currentPath)
    }

    /// ¿El panel activo es la Papelera?
    var activeIsTrash: Bool {
        TrashOps.isTrashPath(activeWorkingPath)
    }

    var secondarySelectedEntries: [FileEntry] {
        secondaryEntries.filter { secondarySelectedIDs.contains($0.id) }
    }

    /// Selección del panel enfocado.
    var activeSelectedEntries: [FileEntry] {
        activeIsSecondary ? secondarySelectedEntries : selectedEntries
    }

    var activeHasSelection: Bool {
        !activeSelectedEntries.isEmpty
    }

    var allSecondarySelected: Bool {
        let ids = secondaryEntries.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { secondarySelectedIDs.contains($0) }
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
        return sizeMeasurementsIncomplete
            ? "Carpeta: ≥ \(FolderSizer.format(folderTotalBytes))"
            : "Carpeta: \(FolderSizer.format(folderTotalBytes))"
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
        selectedIDs = SelectionRangeLogic.toggle(selectedIDs: selectedIDs, id: id)
        selectionAnchorID = id
        selectionFocusID = id
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    func selectRange(to id: String) {
        let ids = visibleEntries.map(\.id)
        let (rangeIDs, anchor) = SelectionRangeLogic.computeRange(ids: ids, anchor: selectionAnchorID ?? selectedIDs.first, target: id)
        selectionAnchorID = anchor
        selectedIDs = rangeIDs
        selectionFocusID = id
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    /// Flechas ↑↓ (y ←→ en lista): mueve el cursor. Con ⇧ extiende el rango
    /// desde el ancla, como en el Explorador de Windows (solo selección).
    func moveSelectionByKeyboard(delta: Int, extending: Bool) {
        if activeIsSecondary {
            moveSecondarySelectionByKeyboard(delta: delta, extending: extending)
            return
        }
        let ids = visibleEntries.map(\.id)
        guard let result = SelectionRangeLogic.nextKeyboardSelection(
            ids: ids,
            currentFocus: selectionFocusID,
            currentAnchor: selectionAnchorID,
            selectedIDs: selectedIDs,
            delta: delta,
            extending: extending
        ) else { return }

        selectedIDs = result.newSelected
        selectionAnchorID = result.newAnchor
        selectionFocusID = result.newFocus
        syncArmedWithSelection()
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
            selectionFocusID = last
        }
        syncArmedWithSelection()
        refreshSelectionStatus()
    }

    func selectAllVisible() {
        if activeIsSecondary {
            selectAllSecondaryVisible()
            return
        }
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

    func clearSecondarySelection() {
        secondarySelectedIDs = []
        secondarySelectionAnchorID = nil
        secondarySelectionFocusID = nil
        statusMessage = "Nada seleccionado (Destino)"
        objectWillChange.send()
    }

    func clearActiveSelection() {
        if activeIsSecondary {
            clearSecondarySelection()
        } else {
            clearSelection()
        }
    }

    func selectActiveOnly(_ id: String) {
        if activeIsSecondary {
            selectSecondaryOnly(id)
        } else {
            selectOnly(id)
        }
    }

    /// Si el naranja está ON, el grupo armado sigue la selección múltiple del panel activo.
    func syncArmedWithSelection() {
        guard hasArmedFileDrag else { return }
        let paths = activeSelectedEntries.map(\.path)
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
        clearSecondarySelection()
        selectionCancelToken &+= 1
        statusMessage = "Selección cancelada"
    }

    /// Clic en zona vacía: no cancelar si hay ⌘/⇧ (evita apagar el naranja al soltar ⌘+clic).
    /// En doble panel también enfoca el panel donde se hizo clic.
    func cancelSelectionFromBackgroundTap(activating pane: PaneFocus? = nil) {
        if let pane, dualPaneEnabled {
            focusPane(pane)
        }
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.shift) { return }
        if dualPaneEnabled, focusedPane == .secondary {
            clearSecondarySelection()
            selectionCancelToken &+= 1
            return
        }
        cancelSelection()
    }

    /// ¿Este path está «cortado» (en bandeja con intención mover)?
    func isCutPending(path: String) -> Bool {
        let key = (path as NSString).standardizingPath
        return shelf.contains {
            $0.intent == .move && ($0.path as NSString).standardizingPath == key
        }
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
        if dualPaneEnabled, focusedPane == .secondary {
            navigateSecondary(to: path)
            return
        }
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
        reload()
        refreshHistoryFlags()
    }

    // MARK: Dual pane

    func toggleDualPane() {
        dualPaneEnabled.toggle()
        if dualPaneEnabled {
            if secondaryPath.isEmpty {
                secondaryPath = currentPath
            }
            focusedPane = .secondary
            reloadSecondary()
            statusMessage = "Dos paneles: izquierda origen · derecha destino. Arrastra o «Mover →»"
        } else {
            secondaryFolderWatcher.stop()
            focusedPane = .primary
            statusMessage = "Un panel"
        }
        objectWillChange.send()
    }

    func focusPane(_ pane: PaneFocus) {
        guard dualPaneEnabled else {
            focusedPane = .primary
            return
        }
        focusedPane = pane
        statusMessage = pane == .primary
            ? "Panel Origen activo · Tab cambia · ⌘⇧→ Destino"
            : "Panel Destino activo · Tab cambia · ⌘⇧← Origen"
        objectWillChange.send()
    }

    /// Alterna Origen ↔ Destino (Tab / menú).
    func toggleFocusedPane() {
        guard dualPaneEnabled else { return }
        focusPane(focusedPane == .primary ? .secondary : .primary)
    }

    func focusOriginPane() {
        guard dualPaneEnabled else { return }
        focusPane(.primary)
    }

    func focusDestinationPane() {
        guard dualPaneEnabled else { return }
        focusPane(.secondary)
    }

    func navigateSecondary(to path: String) {
        let target = (path as NSString).standardizingPath
        guard target != (secondaryPath as NSString).standardizingPath else {
            focusedPane = .secondary
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target, isDirectory: &isDir), isDir.boolValue else {
            secondaryError = "No es una carpeta"
            return
        }
        secondaryPath = target
        secondarySelectedIDs = []
        secondarySelectionAnchorID = nil
        secondarySelectionFocusID = nil
        focusedPane = .secondary
        reloadSecondary()
        statusMessage = "Panel derecho: \((target as NSString).lastPathComponent)"
    }

    func reloadSecondary(preserveSelection: Bool = false, fromWatcher: Bool = false) {
        guard !secondaryPath.isEmpty else {
            secondaryEntries = []
            secondarySelectedIDs = []
            secondarySelectionAnchorID = nil
            secondarySelectionFocusID = nil
            secondaryFolderWatcher.stop()
            return
        }
        // El observador se activa antes de leer para cerrar la ventana en la que
        // una descarga o copia podría ocurrir sin generar una actualización visible.
        if !fromWatcher {
            startWatchingSecondaryFolder()
        }
        let previous = preserveSelection ? secondarySelectedIDs : []
        do {
            let loaded = try loadEntries(at: secondaryPath)
            secondaryEntries = SortEngine.sort(loaded, by: store.preferences.rule(for: secondaryPath))
            secondaryError = nil
            if preserveSelection {
                secondarySelectedIDs = previous.intersection(Set(secondaryEntries.map(\.id)))
            }
        } catch {
            secondaryEntries = []
            if preserveSelection {
                secondarySelectedIDs = []
            }
            secondaryError = error.localizedDescription
        }
        objectWillChange.send()
    }

    private func loadEntries(at path: String) throws -> [FileEntry] {
        // En Papelera siempre incluir ocultos: macOS marca muchos ítems como hidden.
        let includeHidden = showHiddenFiles || TrashOps.isTrashPath(path)
        if flattenFolderView {
            return try DirectoryFlatten.load(
                root: path,
                includeHidden: includeHidden,
                includeDirectories: false
            )
        }
        return try DirectoryLoader.load(path: path, includeHidden: includeHidden)
    }

    func goUpSecondary() {
        let parent = (secondaryPath as NSString).deletingLastPathComponent
        guard parent != secondaryPath, !parent.isEmpty else { return }
        navigateSecondary(to: parent)
    }

    /// Intercambia las carpetas de Origen ↔ Destino.
    func swapPaneFolders() {
        guard dualPaneEnabled else { return }
        let left = currentPath
        let right = secondaryPath
        guard !right.isEmpty, left != right else {
            statusMessage = "No hay carpetas distintas para intercambiar"
            return
        }
        currentPath = right
        secondaryPath = left
        selectedIDs = []
        selectionAnchorID = nil
        selectionFocusID = nil
        secondarySelectedIDs = []
        secondarySelectionAnchorID = nil
        secondarySelectionFocusID = nil
        store.update { $0.lastPath = right }
        reload()
        reloadSecondary()
        statusMessage = "Paneles intercambiados"
    }

    func selectSecondaryOnly(_ id: String) {
        secondarySelectedIDs = [id]
        secondarySelectionAnchorID = id
        secondarySelectionFocusID = id
        focusedPane = .secondary
        refreshSecondarySelectionStatus()
        objectWillChange.send()
    }

    func toggleSecondarySelection(_ id: String) {
        if secondarySelectedIDs.contains(id) {
            secondarySelectedIDs.remove(id)
        } else {
            secondarySelectedIDs.insert(id)
        }
        secondarySelectionAnchorID = id
        secondarySelectionFocusID = id
        focusedPane = .secondary
        refreshSecondarySelectionStatus()
        objectWillChange.send()
    }

    func selectSecondaryRange(to id: String) {
        let ids = secondaryEntries.map(\.id)
        let (rangeIDs, anchor) = SelectionRangeLogic.computeRange(ids: ids, anchor: secondarySelectionAnchorID ?? secondarySelectedIDs.first, target: id)
        secondarySelectionAnchorID = anchor
        secondarySelectedIDs = rangeIDs
        secondarySelectionFocusID = id
        focusedPane = .secondary
        refreshSecondarySelectionStatus()
        objectWillChange.send()
    }

    /// Clic en Destino: ⇧ rango · ⌘ naranja · Varios toggle · normal = uno.
    func clickSelectSecondary(_ id: String) {
        focusedPane = .secondary
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            selectSecondaryRange(to: id)
            if hasArmedFileDrag { syncArmedWithSelection() }
        } else if flags.contains(.command) {
            commandToggleSelect(to: id, pane: .secondary)
        } else if multiSelectMode {
            toggleSecondarySelection(id)
            if hasArmedFileDrag { syncArmedWithSelection() }
        } else {
            if hasArmedFileDrag { clearArmedFileDrag() }
            selectSecondaryOnly(id)
        }
    }

    func applySecondaryMarqueeSelection(hitIDs: Set<String>, base: Set<String>, additive: Bool) {
        focusedPane = .secondary
        if additive {
            secondarySelectedIDs = base.union(hitIDs)
        } else {
            secondarySelectedIDs = hitIDs
        }
        if let last = hitIDs.first {
            secondarySelectionAnchorID = last
            secondarySelectionFocusID = last
        }
        if hasArmedFileDrag { syncArmedWithSelection() }
        refreshSecondarySelectionStatus()
        objectWillChange.send()
    }

    func selectAllSecondaryVisible() {
        secondarySelectedIDs = Set(secondaryEntries.map(\.id))
        secondarySelectionAnchorID = secondaryEntries.first?.id
        secondarySelectionFocusID = secondaryEntries.last?.id ?? secondaryEntries.first?.id
        focusedPane = .secondary
        refreshSecondarySelectionStatus()
        objectWillChange.send()
    }

    func toggleSelectAllSecondary() {
        if allSecondarySelected {
            clearSecondarySelection()
        } else {
            selectAllSecondaryVisible()
        }
    }

    func moveSecondarySelectionByKeyboard(delta: Int, extending: Bool) {
        let ids = secondaryEntries.map(\.id)
        guard let result = SelectionRangeLogic.nextKeyboardSelection(
            ids: ids,
            currentFocus: secondarySelectionFocusID,
            currentAnchor: secondarySelectionAnchorID,
            selectedIDs: secondarySelectedIDs,
            delta: delta,
            extending: extending
        ) else { return }

        secondarySelectedIDs = result.newSelected
        secondarySelectionAnchorID = result.newAnchor
        secondarySelectionFocusID = result.newFocus
        refreshSecondarySelectionStatus()
        objectWillChange.send()
    }

    private func refreshSecondarySelectionStatus() {
        let n = secondarySelectedIDs.count
        if n == 0 {
            statusMessage = "Nada seleccionado (Destino)"
        } else if n == 1, let name = secondarySelectedEntries.first?.name {
            statusMessage = "Destino · 1 seleccionado — \(name)"
        } else {
            statusMessage = "Destino · \(n) seleccionados"
        }
    }

    func openSecondaryEntry(_ entry: FileEntry) {
        if entry.isDirectory {
            navigateSecondary(to: entry.path)
        } else if ArchiveOps.isExtractable(entry.path) {
            extractArchive(entry, intoSecondary: true)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        }
    }

    /// Mueve (o copia) la selección del panel izquierdo al derecho.
    func transferPrimarySelectionToSecondary(copy: Bool = false) {
        guard dualPaneEnabled else { return }
        let paths = selectedEntries.map(\.path)
        guard !paths.isEmpty else {
            let verb = copy ? "copiar" : "mover"
            statusMessage = secondarySelectedIDs.isEmpty
                ? "Para \(verb) a Destino, selecciona algo en Origen (izquierda)"
                : "Esa selección está en Destino. Usa «← Mover» o selecciona en Origen"
            return
        }
        _ = transferPaths(paths, toDirectory: secondaryPath, copy: copy, clearPrimary: true, clearSecondary: false)
    }

    /// Mueve (o copia) la selección del panel derecho al izquierdo (Origen).
    func transferSecondarySelectionToPrimary(copy: Bool = false) {
        guard dualPaneEnabled else { return }
        let paths = secondarySelectedEntries.map(\.path)
        guard !paths.isEmpty else {
            let verb = copy ? "copiar" : "mover"
            statusMessage = selectedIDs.isEmpty
                ? "Para \(verb) a Origen, selecciona algo en Destino (derecha)"
                : "Esa selección está en Origen. Usa «Mover →» o selecciona en Destino"
            return
        }
        _ = transferPaths(paths, toDirectory: currentPath, copy: copy, clearPrimary: false, clearSecondary: true)
    }

    /// Transfiere la selección del panel activo al otro (bidireccional).
    func transferFocusedSelectionToOther(copy: Bool = false) {
        guard dualPaneEnabled else { return }
        if activeIsSecondary {
            transferSecondarySelectionToPrimary(copy: copy)
        } else {
            transferPrimarySelectionToSecondary(copy: copy)
        }
    }

    /// Suelta rutas (Finder / drag interno) en el panel derecho.
    @discardableResult
    func dropPathsOnSecondary(_ paths: [String], copy: Bool) -> Bool {
        transferPaths(paths, toDirectory: secondaryPath, copy: copy, clearPrimary: false, clearSecondary: false)
    }

    /// Suelta rutas en el panel izquierdo (Origen) — p. ej. arrastrando desde Destino.
    @discardableResult
    func dropPathsOnPrimary(_ paths: [String], copy: Bool) -> Bool {
        transferPaths(paths, toDirectory: currentPath, copy: copy, clearPrimary: false, clearSecondary: false)
    }

    @discardableResult
    private func transferPaths(
        _ paths: [String],
        toDirectory dest: String,
        copy: Bool,
        clearPrimary: Bool,
        clearSecondary: Bool
    ) -> Bool {
        guard dualPaneEnabled, !paths.isEmpty else { return false }
        guard pendingMergePreview == nil else {
            statusMessage = "Primero termina o cancela la fusión pendiente"
            return false
        }
        guard AgentPolicy.isPathAllowed(dest) else {
            statusMessage = "Destino no permitido (solo tu carpeta de usuario, /Users/Shared o discos en /Volumes)"
            return false
        }
        let destStd = (dest as NSString).standardizingPath
        let filtered = paths.filter { ($0 as NSString).deletingLastPathComponent != destStd }
        guard !filtered.isEmpty else {
            statusMessage = "Ya están en esa carpeta"
            return false
        }
        let transferPaths = offerMergeIfNeeded(paths: filtered, toDirectory: destStd, move: !copy)
        if pendingMergePreview != nil {
            statusMessage = "Revisa Smart Merge antes de continuar con los demás elementos"
            return true
        }
        guard !transferPaths.isEmpty else { return true }
        enqueueTransfer(paths: transferPaths, toDirectory: destStd, move: !copy) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let pairs):
                if copy {
                    self.pushUndo(.copied(created: pairs.map(\.to)))
                } else {
                    self.pushUndo(.moved(pairs: pairs))
                }
                if clearPrimary { self.clearSelection() }
                if clearSecondary { self.clearSecondarySelection() }
                self.reload()
                self.reloadSecondary()
                let verb = copy ? "Copié" : "Moví"
                let short = (destStd as NSString).lastPathComponent
                self.statusMessage = pairs.count == 1
                    ? "\(verb) 1 ítem → \(short)"
                    : "\(verb) \(pairs.count) ítems → \(short)"
            case .failure(let error):
                self.statusMessage = error.localizedDescription
                self.reload()
                self.reloadSecondary()
            }
        }
        return true
    }

    /// Transfiere con TransferQueue (progreso + verify de tamaño).
    func enqueueTransfer(
        paths: [String],
        toDirectory dest: String,
        move: Bool,
        completion: @escaping (Result<[FileOps.TransferPair], Error>) -> Void
    ) {
        let job = TransferQueue.Job(paths: paths, destinationDir: dest, move: move)
        transferProgressFraction = 0
        transferProgressLabel = move ? "Moviendo…" : "Copiando…"
        statusMessage = transferProgressLabel
        Task { @MainActor in
            do {
                let pairs = try await TransferQueue.shared.run(job) { progress in
                    Task { @MainActor in
                        self.transferProgressFraction = progress.fraction
                        if progress.done {
                            self.transferProgressFraction = nil
                            self.transferProgressLabel = nil
                        } else if !progress.currentName.isEmpty {
                            self.transferProgressLabel = "\(progress.currentName) · \(progress.completed)/\(progress.total)"
                            self.statusMessage = self.transferProgressLabel
                        }
                    }
                }
                completion(.success(pairs))
            } catch {
                self.transferProgressFraction = nil
                self.transferProgressLabel = nil
                completion(.failure(error))
            }
        }
    }

    // MARK: - Diálogos modales (Enter / Esc)

    /// Sheets de confirmación: Enter no debe abrir/renombrar detrás.
    var hasModalSheet: Bool {
        showNewFolderDialog
            || showNewFileDialog
            || showRenameDialog
            || showGoToFolderDialog
            || showDeepSearchDialog
            || showSaveTemplateDialog
            || showOllamaSetupDialog
            || showFolderHandlerSetupDialog
            || pendingMergePreview != nil
    }

    /// Esc cierra el sheet activo (sin acción destructiva).
    @discardableResult
    func dismissModalSheet() -> Bool {
        if showGoToFolderDialog {
            showGoToFolderDialog = false
            return true
        }
        if showDeepSearchDialog {
            showDeepSearchDialog = false
            return true
        }
        if showNewFolderDialog {
            showNewFolderDialog = false
            return true
        }
        if showNewFileDialog {
            showNewFileDialog = false
            return true
        }
        if showRenameDialog {
            showRenameDialog = false
            renameTargetPath = nil
            return true
        }
        if showSaveTemplateDialog {
            showSaveTemplateDialog = false
            return true
        }
        if showOllamaSetupDialog {
            showOllamaSetupDialog = false
            return true
        }
        if showFolderHandlerSetupDialog {
            showFolderHandlerSetupDialog = false
            return true
        }
        if pendingMergePreview != nil {
            cancelPendingMerge()
            return true
        }
        return false
    }

    /// Enter = botón principal del sheet (equivalente a «Ir», «Buscar», «Guardar»…).
    /// Devuelve true si había sheet (aunque el draft esté vacío y no haga nada).
    @discardableResult
    func confirmPrimaryModalAction() -> Bool {
        if showGoToFolderDialog {
            submitGoToFolder()
            return true
        }
        if showDeepSearchDialog {
            submitDeepSearchFromDialog()
            return true
        }
        if showNewFolderDialog {
            let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return true }
            createFolderFromDraft()
            showNewFolderDialog = false
            return true
        }
        if showNewFileDialog {
            let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return true }
            createFileFromDraft()
            showNewFileDialog = false
            return true
        }
        if showRenameDialog {
            let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return true }
            commitRenameFromDraft()
            showRenameDialog = false
            return true
        }
        if showSaveTemplateDialog {
            confirmSaveViewTemplate()
            return true
        }
        if showOllamaSetupDialog {
            // Misma acción primaria del footer: activar si hay Ollama, o seguir sin IA.
            if OllamaClient.shared.available {
                if !OllamaClient.shared.enabled {
                    setOllamaEnabled(true)
                    setOllamaModel(OllamaClient.shared.selectedModel)
                }
            } else {
                setOllamaEnabled(false)
            }
            showOllamaSetupDialog = false
            return true
        }
        if showFolderHandlerSetupDialog {
            navigateToDownloads()
            showFolderHandlerSetupDialog = false
            return true
        }
        if pendingMergePreview != nil {
            // Enter = opción segura («Conservar ambos»), no reemplazar.
            confirmPendingMerge(overwriteConflicts: false)
            return true
        }
        return false
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

    func startDeepSearch(query: String? = nil, includeContent: Bool = false) {
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
        statusMessage = includeContent
            ? "Buscando «\(q)» en nombres y contenido…"
            : "Buscando «\(q)» en subcarpetas…"
        let root = currentPath
        deepSearchTask = Task.detached(priority: .userInitiated) {
            RecursiveSearch.run(
                query: .init(text: q, root: root, searchContent: includeContent),
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
        // Quita también el filtro de la barra de búsqueda (si quedó «*.png»).
        if !searchText.isEmpty {
            searchText = ""
        }
        statusMessage = "Saliste de la búsqueda · orden normal de la carpeta"
    }

    func openDeepSearchHit(_ hit: SearchHit) {
        let path = (hit.path as NSString).standardizingPath
        if hit.isDirectory {
            clearFiltersForReveal()
            navigate(to: path)
            statusMessage = "Abrí carpeta: \((path as NSString).lastPathComponent)"
            return
        }
        let parent = ((path as NSString).deletingLastPathComponent as NSString).standardizingPath
        // Quitar filtro de la barra (p. ej. «*.png») para que el archivo no quede oculto.
        clearFiltersForReveal()
        let current = (currentPath as NSString).standardizingPath
        if parent != current {
            navigate(to: parent)
        }
        // Tras navigate la selección se vacía; re-seleccionar y hacer scroll.
        selectOnly(path)
        requestReveal(path)
        if entries.contains(where: { ($0.path as NSString).standardizingPath == path }) {
            statusMessage = "Seleccionado: \((path as NSString).lastPathComponent)"
        } else {
            statusMessage = "Abrí la carpeta, pero no veo ese archivo en la lista"
        }
    }

    /// Limpia filtros que ocultan filas al revelar un resultado de búsqueda.
    private func clearFiltersForReveal() {
        searchText = ""
        categoryFilter = nil
        if activeAssistantShortcut != nil {
            activeAssistantShortcut = nil
        }
        if downloadsTodayMode {
            downloadsTodayMode = false
        }
    }

    func requestReveal(_ id: String) {
        revealEntryID = (id as NSString).standardizingPath
        revealToken &+= 1
    }

    func confirmPendingMerge(overwriteConflicts: Bool = false) {
        guard let preview = pendingMergePreview else { return }
        let asMove = pendingMergeMove
        let sourcePath = preview.sourcePath
        let destPath = preview.destPath
        statusMessage = "Fusionando…"
        transferProgressFraction = 0
        transferProgressLabel = "Smart Merge…"

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FolderMerge.mergeCopy(
                        source: sourcePath,
                        dest: destPath,
                        overwriteConflicts: overwriteConflicts
                    )
                }.value

                var sourceTrashPath: String?
                if asMove {
                    do {
                        sourceTrashPath = try await Task.detached(priority: .userInitiated) {
                            try FolderMerge.trashSourceAfterVerifiedMerge(result)
                        }.value
                    } catch {
                        await MainActor.run {
                            self.pushUndo(.merged(
                                created: result.pairs.map(\.to),
                                sourceOriginalPath: nil,
                                sourceTrashPath: nil,
                                replacements: result.replacements
                            ))
                            self.pendingMergePreview = nil
                            self.pendingMergeMove = false
                            self.folderDropTargetPath = nil
                            self.clearArmedFileDrag()
                            self.transferProgressFraction = nil
                            self.transferProgressLabel = nil
                            self.reload()
                            self.statusMessage = "Fusioné los archivos, pero conservé el origen porque no pude enviarlo con seguridad a la Papelera: \(error.localizedDescription)"
                        }
                        return
                    }
                }

                await MainActor.run {
                    self.pushUndo(.merged(
                        created: result.pairs.map(\.to),
                        sourceOriginalPath: asMove ? result.sourcePath : nil,
                        sourceTrashPath: sourceTrashPath,
                        replacements: result.replacements
                    ))
                    if asMove {
                        self.shelf.removeAll {
                            ($0.path as NSString).standardizingPath == (sourcePath as NSString).standardizingPath
                        }
                    }
                    self.pendingMergePreview = nil
                    self.pendingMergeMove = false
                    self.folderDropTargetPath = nil
                    self.clearArmedFileDrag()
                    self.transferProgressFraction = nil
                    self.transferProgressLabel = nil
                    self.reload()

                    let name = URL(fileURLWithPath: destPath).lastPathComponent
                    if overwriteConflicts {
                        self.statusMessage = asMove
                            ? "Fusionado reemplazando · origen a Papelera → \(name) · ⌘Z puede restaurar"
                            : "Fusionado reemplazando conflictos → \(name) · ⌘Z puede restaurar"
                    } else {
                        self.statusMessage = asMove
                            ? "Fusionado y origen a Papelera → \(name) · ⌘Z deshace"
                            : "Fusionado → \(name) · ⌘Z deshace"
                    }
                    if !result.warnings.isEmpty {
                        self.statusMessage = (self.statusMessage ?? "") + " · Aviso: " + result.warnings.joined(separator: "; ")
                    }
                }
            } catch {
                let refreshed = await Task.detached(priority: .utility) {
                    FolderMerge.preview(source: sourcePath, dest: destPath)
                }.value
                await MainActor.run {
                    self.transferProgressFraction = nil
                    self.transferProgressLabel = nil
                    self.statusMessage = error.localizedDescription
                    self.pendingMergePreview = refreshed
                }
            }
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
        // Nunca sustituir una vista previa que el usuario ya está revisando.
        guard pendingMergePreview == nil else { return paths }
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
            statusMessage = "Comparando carpetas (Smart Merge)…"
            let source = merge.source
            let destFolder = merge.dest
            Task {
                let preview = await Task.detached(priority: .userInitiated) {
                    FolderMerge.preview(source: source, dest: destFolder)
                }.value
                await MainActor.run {
                    self.pendingMergePreview = preview
                    self.statusMessage = "Revisa la fusión antes de tocar el destino"
                }
            }
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

    /// Abre Terminal.app en la carpeta del panel activo (Origen o Destino).
    func openTerminalHere() {
        let path = (activeWorkingPath as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            statusMessage = "No hay carpeta para Terminal"
            return
        }
        let folderURL = URL(fileURLWithPath: path, isDirectory: true)
        let terminalPaths = [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app"
        ]
        if let appPath = terminalPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [folderURL],
                withApplicationAt: URL(fileURLWithPath: appPath),
                configuration: config
            ) { [weak self] _, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.statusMessage = "No pude abrir Terminal: \(error.localizedDescription)"
                    } else {
                        self.statusMessage = "Terminal en \((path as NSString).lastPathComponent)"
                    }
                }
            }
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", path]
        do {
            try proc.run()
            statusMessage = "Terminal en \((path as NSString).lastPathComponent)"
        } catch {
            statusMessage = "No pude abrir Terminal"
        }
    }

    func runAssistant(prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !agentBusy else {
            appendAgentReply("Todavía estoy con el pedido anterior. Espera un momento…", alsoStatus: true)
            return
        }
        showAssistantPanel = true
        agentBusy = true
        agentProgressLabel = OllamaClient.shared.isReady
            ? "Consultando Ollama («\(OllamaClient.shared.selectedModel)»)"
            : "Interpretando con reglas"
        statusMessage = agentProgressLabel + "…"
        defer {
            agentBusy = false
            agentProgressLabel = ""
        }
        // Pinta banner + puntitos antes de cualquier trabajo pesado.
        await Task.yield()

        appendAgentUser(trimmed)
        agentLog.append("> \(trimmed)")

        if let shortcut = matchAssistantShortcut(prompt: trimmed) {
            applyAssistantShortcut(shortcut)
            return
        }

        let ollama = OllamaClient.shared
        if ollama.isReady {
            agentProgressLabel = "Consultando Ollama («\(ollama.selectedModel)»)"
            statusMessage = agentProgressLabel + "…"
            await Task.yield()
            switch await ollama.proposePlan(prompt: trimmed, currentPath: currentPath) {
            case .plan(let llm):
                agentProgressLabel = "Aplicando plan de Ollama"
                await Task.yield()
                agentPlan = enrichAgentPlan(llm)
                agentLog.append("Plan (Ollama): \(llm.summary)")
            case .unavailable:
                agentProgressLabel = "Ollama no disponible · reglas"
                await Task.yield()
                let plan = AgentIntentParser.plan(from: trimmed, currentPath: currentPath)
                agentPlan = enrichAgentPlan(plan)
                agentLog.append("Plan (reglas): \(plan.summary)")
            case .failed(let reason):
                agentProgressLabel = "Ollama falló · usando reglas"
                await Task.yield()
                appendAgentReply(
                    "Ollama no contestó a tiempo (\(reason)). Sigo con reglas locales.",
                    alsoStatus: true
                )
                let plan = AgentIntentParser.plan(from: trimmed, currentPath: currentPath)
                agentPlan = enrichAgentPlan(plan)
                agentLog.append("Plan (reglas tras fallo Ollama): \(plan.summary)")
            }
        } else {
            agentProgressLabel = "Interpretando con reglas"
            statusMessage = agentProgressLabel + "…"
            await Task.yield()
            let plan = AgentIntentParser.plan(from: trimmed, currentPath: currentPath)
            agentPlan = enrichAgentPlan(plan)
            agentLog.append("Plan (reglas): \(plan.summary)")
        }

        // Lectura: ejecuta solo. Escritura: tarjeta de aprobación (fase 5).
        if let plan = agentPlan, !plan.needsApproval {
            executeAgentPlan(approved: true)
        } else if let plan = agentPlan, plan.needsApproval {
            if plan.steps.isEmpty {
                appendAgentReply(
                    plan.prompt.lowercased().contains("organiza")
                        ? "No hay archivos sueltos para organizar por tipo en esta carpeta."
                        : "No hay nada que hacer con ese pedido en esta carpeta."
                )
                agentPlan = nil
            } else if let block = validateWritePlan(plan) {
                appendAgentReply(block)
                agentPlan = nil
                pendingAgentApproval = nil
            } else {
                pendingAgentApproval = plan
                appendAgentReply(
                    "Esto va a modificar archivos. Revisa el plan y dale a Aprobar si estás de acuerdo.",
                    alsoStatus: true
                )
            }
        }
    }

    /// Si falta selección o destino, no mostramos aprobación a medias.
    private func validateWritePlan(_ plan: AgentPlan) -> String? {
        for step in plan.steps {
            switch step.name {
            case .moveFiles, .copyFiles:
                let destination = step.arguments["destination"] ?? ""
                if destination.isEmpty {
                    return "Dime el destino, por ejemplo: «mueve a Facturas» o «copia a Documentos»."
                }
                if step.pathsArgument.isEmpty {
                    return "Selecciona primero los archivos en la lista y vuelve a pedirlo."
                }
                guard AgentPolicy.isPathAllowed(destination),
                      AgentPolicy.isPathWithinScope(destination, root: currentPath),
                      step.pathsArgument.allSatisfy({
                          AgentPolicy.isPathAllowed($0) && AgentPolicy.isPathWithinScope($0, root: currentPath)
                      }) else {
                    return "El plan incluye una ruta fuera de la carpeta actual o de sus subcarpetas. Navega a esa carpeta y vuelve a intentarlo."
                }
            case .createDirectory:
                let name = (step.arguments["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let parent = step.arguments["parent"] ?? currentPath
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                    return "El nombre de la carpeta debe ser un solo nombre, sin rutas ni «..»."
                }
                guard AgentPolicy.isPathAllowed(parent),
                      AgentPolicy.isPathWithinScope(parent, root: currentPath) else {
                    return "No puedo crear esa carpeta fuera de la carpeta actual."
                }
            case .renameFiles:
                let newName = step.arguments["newName"] ?? ""
                let path = step.arguments["path"] ?? step.pathsArgument.first ?? ""
                if newName.isEmpty || path.isEmpty {
                    return "Selecciona un archivo o carpeta y di «renombra a nombre-nuevo»."
                }
                guard AgentPolicy.isPathAllowed(path),
                      AgentPolicy.isPathWithinScope(path, root: currentPath) else {
                    return "No puedo renombrar elementos fuera de la carpeta actual."
                }
            default:
                break
            }
        }
        return nil
    }

    /// Rellena rutas de la selección y expande «organizar» a crear+mover concretos.
    private func enrichAgentPlan(_ plan: AgentPlan) -> AgentPlan {
        var steps: [AgentToolCall] = []
        for step in plan.steps {
            switch step.name {
            case .organizeFiles:
                let built = buildOrganizeSteps(in: step.arguments["path"] ?? currentPath)
                if built.isEmpty {
                    // Dejamos el organize vacío → el caller avisa.
                } else {
                    steps.append(contentsOf: built)
                }
            case .moveFiles, .copyFiles, .renameFiles:
                var args = step.arguments
                if args["paths"] == nil || (args["paths"] ?? "").isEmpty {
                    let paths = selectedEntries.map(\.path)
                    if !paths.isEmpty {
                        args["paths"] = paths.joined(separator: "\n")
                    }
                }
                if step.name == .renameFiles, args["path"] == nil, let first = selectedEntries.first {
                    args["path"] = first.path
                }
                if step.name == .moveFiles || step.name == .copyFiles,
                   let destination = args["destination"],
                   !destination.hasPrefix("/") && !destination.hasPrefix("~") {
                    args["destination"] = (currentPath as NSString).appendingPathComponent(destination)
                }
                steps.append(AgentToolCall(name: step.name, arguments: args, risk: step.risk))
            default:
                steps.append(step)
            }
        }
        let summary: String
        if steps.contains(where: { $0.name == .createDirectory || $0.name == .moveFiles }),
           plan.steps.contains(where: { $0.name == .organizeFiles }) {
            summary = "Organizar por tipo: \(steps.count) pasos"
        } else {
            summary = plan.summary
        }
        return AgentPlan(id: plan.id, prompt: plan.prompt, summary: summary, steps: steps, createdAt: plan.createdAt)
    }

    /// Crea carpetas por categoría y mueve los archivos de primer nivel.
    private func buildOrganizeSteps(in folder: String) -> [AgentToolCall] {
        let folderStd = (folder as NSString).standardizingPath
        let direct = entries.filter { entry in
            guard !entry.isDirectory else { return false }
            let parent = ((entry.path as NSString).deletingLastPathComponent as NSString).standardizingPath
            return parent == folderStd
        }
        var byCategory: [FileCategory: [FileEntry]] = [:]
        for entry in direct {
            byCategory[entry.category, default: []].append(entry)
        }
        var steps: [AgentToolCall] = []
        for category in FileCategory.allCases where category != .folder {
            guard let group = byCategory[category], !group.isEmpty else { continue }
            let folderName = category.organizeFolderName
            let dest = (folder as NSString).appendingPathComponent(folderName)
            steps.append(AgentToolCall(
                name: .createDirectory,
                arguments: ["name": folderName, "parent": folder],
                risk: .write
            ))
            steps.append(AgentToolCall(
                name: .moveFiles,
                arguments: [
                    "paths": group.map(\.path).joined(separator: "\n"),
                    "destination": dest
                ],
                risk: .write
            ))
        }
        return steps
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
                startDeepSearch(query: q, includeContent: false)
                appendAgentReply(
                    "Busco archivos cuyo nombre coincida con «\(q)» en esta carpeta y subcarpetas. Mira la lista o el filtro de búsqueda."
                )
            case .searchContent:
                let q = step.arguments["query"] ?? plan.prompt
                startDeepSearch(query: q, includeContent: true)
                appendAgentReply(
                    "Busco «\(q)» en nombres y dentro de archivos de texto/código de esta carpeta y abajo."
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
                // Ya se expandió en enrichAgentPlan; si llega aquí, no había archivos.
                appendAgentReply("No encontré archivos sueltos para organizar por tipo aquí.")
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
            case .createDirectory:
                executeCreateDirectory(step)
            case .copyFiles:
                executeTransfer(step, move: false)
            case .moveFiles:
                executeTransfer(step, move: true)
            case .renameFiles:
                executeRename(step)
            }
        }
        if !plan.needsApproval || approved {
            agentPlan = nil
            pendingAgentApproval = nil
        }
    }

    private func executeCreateDirectory(_ step: AgentToolCall) {
        let name = (step.arguments["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = step.arguments["parent"] ?? currentPath
        guard !name.isEmpty else {
            appendAgentReply("No me diste nombre para la carpeta.")
            return
        }
        guard AgentPolicy.isPathAllowed(parent),
              AgentPolicy.isPathWithinScope(parent, root: currentPath),
              name != ".", name != "..", !name.contains("/") else {
            appendAgentReply("La ruta o el nombre de la carpeta no están permitidos.")
            return
        }
        // Si ya existe (p. ej. al organizar), reutilízala.
        let existing = (parent as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: existing) {
            appendAgentReply("La carpeta «\(name)» ya estaba; la reutilizo.")
            return
        }
        do {
            let created = try FileOps.createFolder(named: name, in: parent)
            pushUndo(.copied(created: [created])) // deshacer = papelera de la carpeta nueva vacía/casi
            if parent == currentPath { reload() }
            appendAgentReply("Creé la carpeta «\((created as NSString).lastPathComponent)».")
        } catch {
            appendAgentReply("No pude crear la carpeta: \(error.localizedDescription)")
        }
    }

    private func executeTransfer(_ step: AgentToolCall, move: Bool) {
        let paths = step.pathsArgument
        let dest = (step.arguments["destination"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paths.isEmpty else {
            appendAgentReply(
                move
                    ? "Selecciona algo y di p. ej. «mueve a Facturas»."
                    : "Selecciona algo y di p. ej. «copia a Facturas»."
            )
            return
        }
        guard !dest.isEmpty else {
            appendAgentReply("Falta el destino. Prueba «mueve a NombreCarpeta».")
            return
        }
        guard AgentPolicy.isPathAllowed(dest),
              AgentPolicy.isPathWithinScope(dest, root: currentPath),
              paths.allSatisfy({
                  AgentPolicy.isPathAllowed($0) && AgentPolicy.isPathWithinScope($0, root: currentPath)
              }) else {
            appendAgentReply("Alguna ruta está fuera de la carpeta actual o no está permitida.")
            return
        }
        // Crear destino si es carpeta relativa que aún no existe.
        var destIsDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dest, isDirectory: &destIsDir) {
            do {
                try FileManager.default.createDirectory(
                    atPath: dest,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                destIsDir = true
            } catch {
                appendAgentReply("No pude preparar el destino: \(error.localizedDescription)")
                return
            }
        }
        guard destIsDir.boolValue || FileManager.default.fileExists(atPath: dest) else {
            appendAgentReply("El destino no es una carpeta.")
            return
        }
        // Si dest es archivo (raro), abortar.
        var check: ObjCBool = false
        FileManager.default.fileExists(atPath: dest, isDirectory: &check)
        guard check.boolValue else {
            appendAgentReply("El destino tiene que ser una carpeta.")
            return
        }
        enqueueTransfer(paths: paths, toDirectory: dest, move: move) { result in
            switch result {
            case .success(let pairs):
                if move {
                    self.pushUndo(.moved(pairs: pairs))
                } else {
                    self.pushUndo(.copied(created: pairs.map(\.to)))
                }
                self.reload()
                let verb = move ? "Moví" : "Copié"
                self.appendAgentReply(
                    pairs.count == 1
                        ? "\(verb) 1 ítem a «\((dest as NSString).lastPathComponent)»."
                        : "\(verb) \(pairs.count) ítems a «\((dest as NSString).lastPathComponent)»."
                )
            case .failure(let error):
                self.appendAgentReply("No pude \(move ? "mover" : "copiar"): \(error.localizedDescription)")
            }
        }
    }

    private func executeRename(_ step: AgentToolCall) {
        let newName = (step.arguments["newName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let path = step.arguments["path"] ?? step.pathsArgument.first ?? selectedEntries.first?.path
        guard let path, !newName.isEmpty else {
            appendAgentReply("Selecciona un ítem y di «renombra a nombre-nuevo».")
            return
        }
        guard AgentPolicy.isPathAllowed(path),
              AgentPolicy.isPathWithinScope(path, root: currentPath) else {
            appendAgentReply("Esa ruta está fuera de la carpeta actual o no está permitida.")
            return
        }
        do {
            let newPath = try FileOps.rename(path: path, to: newName)
            pushUndo(.moved(pairs: [.init(from: path, to: newPath)]))
            reload()
            selectOnly(newPath)
            appendAgentReply("Renombré a «\(newName)».")
        } catch {
            appendAgentReply("No pude renombrar: \(error.localizedDescription)")
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

    func setShowHiddenFiles(_ on: Bool) {
        showHiddenFiles = on
        store.update { $0.showHiddenFiles = on }
        reload(preserveSelection: true)
        if dualPaneEnabled { reloadSecondary(preserveSelection: true) }
        statusMessage = on ? "Mostrando ocultos" : "Ocultos escondidos"
    }

    func toggleShowHiddenFiles() {
        setShowHiddenFiles(!showHiddenFiles)
    }

    func setFlattenFolderView(_ on: Bool) {
        flattenFolderView = on
        store.update { $0.flattenFolderView = on }
        reload(preserveSelection: true)
        if dualPaneEnabled { reloadSecondary(preserveSelection: true) }
        statusMessage = on ? "Vista plana (archivos anidados)" : "Vista de carpeta"
    }

    func toggleFlattenFolderView() {
        setFlattenFolderView(!flattenFolderView)
    }

    func beginPathOmnibox() {
        pathOmniboxDraft = currentPath
        pathOmniboxEditing = true
        showGoToFolderDialog = false
    }

    func cancelPathOmnibox() {
        pathOmniboxEditing = false
        pathOmniboxDraft = ""
    }

    func submitPathOmnibox() {
        let raw = pathOmniboxDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        pathOmniboxEditing = false
        guard !raw.isEmpty else { return }
        goToFolderDraft = raw
        submitGoToFolder()
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
        if dualPaneEnabled, focusedPane == .secondary {
            goUpSecondary()
            return
        }
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
        DropPathCollector.collect(providers) { paths in
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
        let folderKey = (currentPath as NSString).standardizingPath
        store.update { prefs in
            switch scope {
            case .thisFolder:
                prefs.folderOverrides[folderKey] = newRule
            case .everywhere:
                prefs.globalRule = newRule
                prefs.folderOverrides = [:]
            }
        }
        statusMessage = scope == .everywhere
            ? "Orden guardado en todas las carpetas"
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

    /// Aplica una plantilla guardada (orden + vista + filtro) y la deja como default.
    func applyViewTemplate(_ template: ViewTemplate) {
        downloadsTodayMode = false
        activeAssistantShortcut = nil
        applyRule(template.rule, scope: .everywhere)
        setViewMode(template.viewMode)
        categoryFilter = template.categoryFilter
        activeViewTemplateID = template.id
        statusMessage = "Plantilla «\(template.name)» aplicada"
        objectWillChange.send()
    }

    func promptSaveViewTemplate() {
        templateNameDraft = ""
        showSaveTemplateDialog = true
    }

    func confirmSaveViewTemplate() {
        let name = templateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if viewTemplates.count >= ViewTemplate.maxCount {
            statusMessage = "Máximo \(ViewTemplate.maxCount) plantillas"
            showSaveTemplateDialog = false
            return
        }
        let template = ViewTemplate(
            name: name,
            rule: rule,
            viewMode: viewMode,
            categoryFilter: categoryFilter
        )
        viewTemplates.append(template)
        store.update { $0.viewTemplates = viewTemplates }
        activeViewTemplateID = template.id
        showSaveTemplateDialog = false
        statusMessage = "Plantilla «\(name)» guardada"
    }

    func deleteViewTemplate(_ template: ViewTemplate) {
        viewTemplates.removeAll { $0.id == template.id }
        if activeViewTemplateID == template.id {
            activeViewTemplateID = nil
        }
        store.update { $0.viewTemplates = viewTemplates }
        statusMessage = "Plantilla «\(template.name)» eliminada"
    }

    /// Orden por peso: lo más pesado arriba (no borra nada). Se guarda como default.
    func showHeaviestForCleanup() {
        downloadsTodayMode = false
        activeAssistantShortcut = nil
        applyRule(.heaviestFirst, scope: .everywhere)
        let msg = "Listo: ordené por peso y lo dejé guardado. Arriba está lo que más ocupa. No borré nada."
        appendAgentReply(msg)
    }

    func exitCleanupMode() {
        // Vuelve al estilo Descargas y lo guarda (si no, al reiniciar seguiría en pesados).
        applyRule(.downloads, scope: .everywhere)
        appendAgentReply("Volviste al orden normal (estilo Descargas) y lo guardé.")
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

    // MARK: Atajos de teclado

    var keyboardHotkeyOverrides: [String: KeyChord] {
        store.preferences.keyboardHotkeyOverrides
    }

    func chord(forHotkey id: String) -> KeyChord? {
        AppHotkeyCatalog.resolvedChord(id: id, overrides: keyboardHotkeyOverrides)
    }

    func setKeyboardHotkey(_ id: String, chord: KeyChord) {
        guard let def = AppHotkeyCatalog.definition(id: id), def.isEditable else { return }
        store.update { prefs in
            if chord == def.defaultChord {
                prefs.keyboardHotkeyOverrides.removeValue(forKey: id)
            } else {
                prefs.keyboardHotkeyOverrides[id] = chord
            }
        }
        objectWillChange.send()
        if id == "nav.globalOpen" {
            GlobalHotKey.reload()
        }
    }

    func resetKeyboardHotkey(_ id: String) {
        store.update { $0.keyboardHotkeyOverrides.removeValue(forKey: id) }
        objectWillChange.send()
        if id == "nav.globalOpen" {
            GlobalHotKey.reload()
        }
    }

    func restoreDefaultKeyboardHotkeys() {
        store.update { $0.keyboardHotkeyOverrides = [:] }
        objectWillChange.send()
        GlobalHotKey.reload()
    }

    var globalHotkeyFolderPath: String {
        if let custom = store.preferences.globalHotkeyFolderPath,
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return (custom as NSString).standardizingPath
        }
        return GlobalHotKey.defaultDownloadsPath()
    }

    var globalHotkeyFolderDisplayName: String {
        URL(fileURLWithPath: globalHotkeyFolderPath).lastPathComponent
    }

    var usesCustomGlobalHotkeyFolder: Bool {
        store.preferences.globalHotkeyFolderPath != nil
    }

    func setGlobalHotkeyFolder(_ path: String?) {
        store.update { prefs in
            if let path, !path.isEmpty {
                prefs.globalHotkeyFolderPath = (path as NSString).standardizingPath
            } else {
                prefs.globalHotkeyFolderPath = nil
            }
        }
        objectWillChange.send()
        let name = globalHotkeyFolderDisplayName
        statusMessage = "Atajo ⌃⌥O abre «\(name)»"
    }

    func pickGlobalHotkeyFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Carpeta que abrirá Findaro con ⌃⌥O"
        panel.prompt = "Usar esta carpeta"
        panel.directoryURL = URL(fileURLWithPath: globalHotkeyFolderPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setGlobalHotkeyFolder(url.path)
    }

    func resetGlobalHotkeyFolder() {
        setGlobalHotkeyFolder(nil)
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
        } else if ArchiveOps.isExtractable(entry.path) {
            extractArchive(entry, intoSecondary: false)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        }
    }

    /// Descomprime zip/tar en esta carpeta y abre el resultado en Findaro (sin Finder).
    func extractArchive(_ entry: FileEntry, intoSecondary: Bool? = nil) {
        let path = entry.path
        guard ArchiveOps.isExtractable(path) else {
            statusMessage = "No puedo descomprimir «\(entry.name)» aquí — usa Abrir con"
            return
        }
        let secondary = intoSecondary ?? activeIsSecondary
        statusMessage = "Descomprimiendo \(entry.name)…"
        Task.detached {
            do {
                let result = try ArchiveOps.extract(archivePath: path)
                await MainActor.run {
                    self.finishExtract(resultPath: result, intoSecondary: secondary, archiveName: entry.name)
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "No se pudo descomprimir: \(error.localizedDescription)"
                }
            }
        }
    }

    private func finishExtract(resultPath: String, intoSecondary: Bool, archiveName: String) {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resultPath, isDirectory: &isDir)
        guard exists else {
            statusMessage = "Descomprimí \(archiveName), pero no encuentro el resultado"
            if intoSecondary { reloadSecondary() } else { reload() }
            return
        }
        let name = URL(fileURLWithPath: resultPath).lastPathComponent
        if intoSecondary {
            reloadSecondary()
            if isDir.boolValue {
                navigateSecondary(to: resultPath)
            } else {
                selectSecondaryOnly(resultPath)
            }
        } else {
            reload()
            if dualPaneEnabled { reloadSecondary() }
            if isDir.boolValue {
                navigate(to: resultPath)
            } else {
                selectOnly(resultPath)
            }
        }
        statusMessage = "Descomprimido: \(name)"
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
        let targets = activeSelectedEntries
        let paths = targets.map(\.path)
        guard !paths.isEmpty else {
            statusMessage = "Selecciona algo para comprimir"
            return
        }
        let folder = activeWorkingPath
        let intoSecondary = activeIsSecondary
        let destName: String = {
            if paths.count == 1 {
                let base = URL(fileURLWithPath: paths[0]).deletingPathExtension().lastPathComponent
                return "\(base).zip"
            }
            return "Archivo.zip"
        }()
        var dest = (folder as NSString).appendingPathComponent(destName)
        var n = 2
        while FileManager.default.fileExists(atPath: dest) {
            let stem = URL(fileURLWithPath: destName).deletingPathExtension().lastPathComponent
            dest = (folder as NSString).appendingPathComponent("\(stem) \(n).zip")
            n += 1
        }
        statusMessage = "Comprimiendo…"
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
                        if intoSecondary {
                            self.reloadSecondary()
                        } else {
                            self.reload()
                        }
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
        guard let first = activeSelectedEntries.first else { return }
        if activeIsSecondary {
            openSecondaryEntry(first)
        } else {
            open(first)
        }
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
        let paths = activeSelectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        QuickLookController.shared.toggle(browser: self, focusing: paths)
    }

    func moveSelectionToTrash() {
        // Dentro de la Papelera: borrar para siempre (como Finder).
        if activeIsTrash {
            permanentlyDeleteSelection(confirm: true)
            return
        }
        let targets = activeSelectedEntries
        guard !targets.isEmpty else { return }
        statusMessage = "Enviando a la Papelera…"
        let snapshot = targets.map { (path: $0.path, name: $0.name) }
        let trashedSecondary = activeIsSecondary
        clearActiveSelection()

        Task {
            var moved = 0
            var failures: [String] = []
            for item in snapshot {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try FileManager.default.trashItem(
                            at: URL(fileURLWithPath: item.path),
                            resultingItemURL: nil
                        )
                    }.value
                    moved += 1
                } catch {
                    failures.append("\(item.name): \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                self.reload()
                if self.dualPaneEnabled {
                    self.reloadSecondary()
                }
                var parts: [String] = []
                if moved > 0 {
                    let whereLabel = trashedSecondary ? " (Destino)" : ""
                    parts.append(moved == 1
                        ? "1 elemento a la Papelera\(whereLabel)"
                        : "\(moved) elementos a la Papelera\(whereLabel)")
                }
                if !failures.isEmpty {
                    parts.append("Fallaron \(failures.count): " + failures.prefix(3).joined(separator: "; "))
                }
                self.statusMessage = parts.isEmpty ? "Nada enviado a la Papelera" : parts.joined(separator: " · ")
            }
        }
    }

    /// Borra de verdad lo seleccionado (solo tiene sentido en la Papelera).
    func permanentlyDeleteSelection(confirm: Bool) {
        let targets = activeSelectedEntries
        guard !targets.isEmpty else {
            statusMessage = "Selecciona algo en la Papelera"
            return
        }
        if confirm {
            let alert = NSAlert()
            alert.messageText = targets.count == 1
                ? "¿Eliminar «\(targets[0].name)» para siempre?"
                : "¿Eliminar \(targets.count) elementos para siempre?"
            alert.informativeText = "No se pueden recuperar desde la Papelera."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Eliminar para siempre")
            alert.addButton(withTitle: "Cancelar")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let paths = targets.map(\.path)
        clearActiveSelection()
        statusMessage = "Eliminando…"
        Task {
            let result: (ok: Int, failures: [String]) = await Task.detached(priority: .userInitiated) {
                do {
                    return try TrashOps.permanentlyDelete(paths: paths)
                } catch {
                    return (ok: 0, failures: [error.localizedDescription])
                }
            }.value
            await MainActor.run {
                self.reload()
                if self.dualPaneEnabled { self.reloadSecondary() }
                var parts: [String] = []
                if result.ok > 0 {
                    parts.append(result.ok == 1
                        ? "1 eliminado para siempre"
                        : "\(result.ok) eliminados para siempre")
                }
                if !result.failures.isEmpty {
                    parts.append("Fallaron \(result.failures.count): "
                        + result.failures.prefix(2).joined(separator: "; "))
                }
                self.statusMessage = parts.joined(separator: " · ")
            }
        }
    }

    /// Vacía toda la Papelera del usuario.
    func emptyTrash(confirm: Bool) {
        if confirm {
            let alert = NSAlert()
            alert.messageText = "¿Vaciar la Papelera?"
            alert.informativeText = "Se eliminarán para siempre todos los elementos de la Papelera."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Vaciar Papelera")
            alert.addButton(withTitle: "Cancelar")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        // Asegura que estamos en la ruta canónica.
        if !isViewingTrash {
            navigate(to: TrashOps.userTrashPath, recordHistory: true)
        }
        statusMessage = "Vaciando Papelera…"
        Task {
            let result: (ok: Int, failures: [String]) = await Task.detached(priority: .userInitiated) {
                do {
                    return try TrashOps.emptyUserTrash()
                } catch {
                    // Sin Acceso completo al disco: pedir a Finder.
                    if TrashOps.isPermissionError(error) {
                        let script = """
                        tell application "Finder"
                          empty the trash
                        end tell
                        """
                        var err: NSDictionary?
                        if let apple = NSAppleScript(source: script) {
                            _ = apple.executeAndReturnError(&err)
                            if err == nil {
                                return (ok: -1, failures: [])
                            }
                            let msg = (err?[NSAppleScript.errorMessage] as? String)
                                ?? error.localizedDescription
                            return (ok: 0, failures: [msg])
                        }
                    }
                    return (ok: 0, failures: [error.localizedDescription])
                }
            }.value
            await MainActor.run {
                self.reload()
                if result.ok < 0 {
                    self.statusMessage = "Papelera vaciada (Finder)"
                } else if result.ok == 0, result.failures.isEmpty {
                    self.statusMessage = "La Papelera ya estaba vacía"
                } else {
                    var parts: [String] = []
                    if result.ok > 0 {
                        parts.append("Papelera: \(result.ok) eliminados")
                    }
                    if !result.failures.isEmpty {
                        parts.append(result.failures.prefix(2).joined(separator: "; "))
                    }
                    self.statusMessage = parts.joined(separator: " · ")
                }
            }
        }
    }

    func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    func navigateToTrash() {
        navigate(to: TrashOps.userTrashPath, recordHistory: true)
    }

    // MARK: - Crear / renombrar / duplicar / portapapeles

    func promptNewFolder() {
        nameDraft = "Carpeta sin título"
        showNewFolderDialog = true
    }

    func createFolderFromDraft() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = activeWorkingPath
        let intoSecondary = activeIsSecondary
        do {
            let path = try FileOps.createFolder(named: name, in: folder)
            pushUndo(.copied(created: [path]))
            if intoSecondary {
                reloadSecondary()
                selectSecondaryOnly(path)
            } else {
                reload()
                selectOnly(path)
            }
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
        let folder = activeWorkingPath
        let intoSecondary = activeIsSecondary
        do {
            let path = try FileOps.createFile(named: name, in: folder)
            pushUndo(.copied(created: [path]))
            if intoSecondary {
                reloadSecondary()
                selectSecondaryOnly(path)
            } else {
                reload()
                selectOnly(path)
            }
            statusMessage = "Archivo creado: \(URL(fileURLWithPath: path).lastPathComponent)"
        } catch {
            statusMessage = "No se pudo crear: \(error.localizedDescription)"
        }
    }

    func promptRename() {
        guard let entry = activeSelectedEntries.first else {
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
        let intoSecondary = dualPaneEnabled && paneForPath(path) == .secondary
        do {
            let newPath = try FileOps.rename(path: path, to: newName)
            pushUndo(.moved(pairs: [.init(from: path, to: newPath)]))
            if intoSecondary {
                reloadSecondary()
                if dualPaneEnabled { reload() }
                selectSecondaryOnly(newPath)
            } else {
                reload()
                if dualPaneEnabled { reloadSecondary() }
                selectOnly(newPath)
            }
            statusMessage = "Renombrado a \(newName)"
        } catch {
            statusMessage = "No se pudo renombrar: \(error.localizedDescription)"
        }
        renameTargetPath = nil
    }

    func duplicateSelection() {
        let targets = activeSelectedEntries
        guard !targets.isEmpty else {
            statusMessage = "Selecciona algo para duplicar"
            return
        }
        statusMessage = "Duplicando…"
        let paths = targets.map(\.path)
        let names = Dictionary(uniqueKeysWithValues: targets.map { ($0.path, $0.name) })
        let intoSecondary = activeIsSecondary

        Task {
            var lastPath: String?
            var createdPaths: [String] = []
            var failure: String?
            for path in paths {
                do {
                    let created = try await Task.detached(priority: .userInitiated) {
                        try FileOps.duplicate(path: path)
                    }.value
                    lastPath = created
                    createdPaths.append(created)
                } catch {
                    let name = names[path] ?? URL(fileURLWithPath: path).lastPathComponent
                    failure = createdPaths.isEmpty
                        ? "No se pudo duplicar \(name): \(error.localizedDescription)"
                        : "Duplicación parcial (\(createdPaths.count) elemento(s)); ⌘Z deshace lo creado. \(error.localizedDescription)"
                    break
                }
            }
            await MainActor.run {
                if !createdPaths.isEmpty { self.pushUndo(.copied(created: createdPaths)) }
                if intoSecondary {
                    self.reloadSecondary()
                    if self.dualPaneEnabled { self.reload() }
                    if let lastPath, failure == nil {
                        self.selectSecondaryOnly(lastPath)
                    }
                } else {
                    self.reload()
                    if self.dualPaneEnabled { self.reloadSecondary() }
                    if let lastPath, failure == nil {
                        self.selectOnly(lastPath)
                    }
                }
                if let failure {
                    self.statusMessage = failure
                } else {
                    self.statusMessage = createdPaths.count == 1
                        ? "Duplicado · ⌘Z deshace"
                        : "\(createdPaths.count) duplicados · ⌘Z deshace"
                }
            }
        }
    }

    /// Paths que se armarían si haces hold sobre `entry` (selección múltiple incluida).
    func dragArmGroup(for entry: FileEntry, pane: PaneFocus? = nil) -> [String] {
        let target = pane ?? paneForPath(entry.path)
        if dualPaneEnabled, target == .secondary {
            if secondarySelectedIDs.contains(entry.id), secondarySelectedIDs.count > 1 {
                return secondarySelectedEntries.map(\.path)
            }
            return [entry.path]
        }
        if selectedIDs.contains(entry.id), selectedIDs.count > 1 {
            return selectedEntries.map(\.path)
        }
        return [entry.path]
    }

    /// Empieza el anillo de progreso al pulsar (antes de los 1s).
    func beginArmingFileDrag(for entry: FileEntry, pane: PaneFocus? = nil) {
        let target = pane ?? paneForPath(entry.path)
        if dualPaneEnabled {
            focusedPane = target
        }
        // Si ya estamos armando este gesto, no reinicies el anillo.
        if fileDragArmingPrimaryPath == entry.path, armingProgressTask != nil { return }
        if isFileDragArmed(path: entry.path) { return }

        armingProgressTask?.cancel()
        let group = dragArmGroup(for: entry, pane: target)
        fileDragArmingPaths = Set(group)
        fileDragArmingPrimaryPath = entry.path
        fileDragArmProgress = 0
        let path = entry.path
        let entryCopy = entry
        let armPane = target
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
            self.armFileDrag(for: entryCopy, pane: armPane)
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
    func armFileDrag(for entry: FileEntry, pane: PaneFocus? = nil) {
        commandRangeSelectForMove(to: entry.id, pane: pane ?? paneForPath(entry.path))
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
        return startDragWithPaths(paths)
    }

    /// Inicia arrastre nativo con una lista arbitraria de rutas seleccionadas.
    @discardableResult
    func startDragWithPaths(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else { return false }
        FolderDragBridge.shared.onSessionEnded = { [weak self] dropped in
            guard let self, dropped else { return }
            self.clearArmedFileDrag()
            self.reload()
            if self.dualPaneEnabled { self.reloadSecondary() }
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
        guard pendingMergePreview == nil else {
            statusMessage = "Primero termina o cancela la fusión pendiente"
            return
        }
        let paths = urls.map(\.path)
        let dest = activeWorkingPath
        let rest = offerMergeIfNeeded(paths: paths, toDirectory: dest, move: false)
        if pendingMergePreview != nil {
            statusMessage = "Revisa Smart Merge; vuelve a pegar para continuar con los demás elementos"
            return
        }
        guard !rest.isEmpty else { return }
        enqueueTransfer(paths: rest, toDirectory: dest, move: false) { result in
            switch result {
            case .success(let pairs):
                self.pushUndo(.copied(created: pairs.map(\.to)))
                self.reload()
                if self.dualPaneEnabled { self.reloadSecondary() }
                self.statusMessage = pairs.count == 1 ? "1 archivo pegado" : "\(pairs.count) archivos pegados"
            case .failure(let error):
                self.statusMessage = "No se pudo pegar: \(error.localizedDescription)"
            }
        }
    }

    var canPasteFiles: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }

    // MARK: - Bandeja (Dropover casero)

    func addSelectionToShelf(intent: FileOps.ShelfIntent = .move) {
        let entries = activeSelectedEntries
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
        guard pendingMergePreview == nil else {
            statusMessage = "Primero termina o cancela la fusión pendiente"
            return
        }

        let dest = activeWorkingPath
        let originalItems = shelf
        var remaining: [FileOps.ShelfItem] = []
        var toMove: [String] = []
        var toCopy: [String] = []
        var copyKeepOnShelf: [FileOps.ShelfItem] = []

        for (index, item) in originalItems.enumerated() {
            let move = item.intent == .move
            let paths = offerMergeIfNeeded(paths: [item.path], toDirectory: dest, move: move)
            if pendingMergePreview != nil {
                remaining.append(contentsOf: originalItems[index...])
                break
            }
            if move {
                toMove.append(contentsOf: paths)
            } else {
                toCopy.append(contentsOf: paths)
                copyKeepOnShelf.append(item)
            }
        }

        if pendingMergePreview != nil {
            shelf = remaining
            statusMessage = "Revisa Smart Merge; los demás elementos siguen en la bandeja"
            return
        }

        // Primero moves, luego copies — ambos por TransferQueue.
        func finish(
            moved: [FileOps.TransferPair],
            copied: [FileOps.TransferPair],
            error: String?,
            restoreShelf: [FileOps.ShelfItem]?
        ) {
            if let restoreShelf {
                shelf = restoreShelf
            } else {
                // Moves salen de la bandeja; copias pueden permanecer.
                shelf = remaining + copyKeepOnShelf
            }
            if !moved.isEmpty { pushUndo(.moved(pairs: moved)) }
            if !copied.isEmpty { pushUndo(.copied(created: copied.map(\.to))) }
            reload()
            if dualPaneEnabled { reloadSecondary() }
            var parts: [String] = []
            if !moved.isEmpty { parts.append("\(moved.count) movido(s)") }
            if !copied.isEmpty { parts.append("\(copied.count) copiado(s)") }
            if let error {
                statusMessage = parts.isEmpty
                    ? "No se completó la transferencia: \(error)"
                    : "Transferencia parcial: \(parts.joined(separator: " · ")). \(error)"
            } else {
                statusMessage = parts.isEmpty ? "Nada transferido" : parts.joined(separator: " · ") + " · ⌘Z deshace"
            }
        }

        if toMove.isEmpty && toCopy.isEmpty {
            shelf = remaining
            reload()
            if dualPaneEnabled { reloadSecondary() }
            statusMessage = "Nada transferido"
            return
        }

        if !toMove.isEmpty {
            enqueueTransfer(paths: toMove, toDirectory: dest, move: true) { moveResult in
                switch moveResult {
                case .success(let movedPairs):
                    if toCopy.isEmpty {
                        finish(moved: movedPairs, copied: [], error: nil, restoreShelf: nil)
                    } else {
                        self.enqueueTransfer(paths: toCopy, toDirectory: dest, move: false) { copyResult in
                            switch copyResult {
                            case .success(let copiedPairs):
                                finish(moved: movedPairs, copied: copiedPairs, error: nil, restoreShelf: nil)
                            case .failure(let error):
                                finish(
                                    moved: movedPairs,
                                    copied: [],
                                    error: error.localizedDescription,
                                    restoreShelf: remaining + copyKeepOnShelf
                                )
                            }
                        }
                    }
                case .failure(let error):
                    finish(
                        moved: [],
                        copied: [],
                        error: error.localizedDescription,
                        restoreShelf: originalItems
                    )
                }
            }
        } else {
            enqueueTransfer(paths: toCopy, toDirectory: dest, move: false) { copyResult in
                switch copyResult {
                case .success(let copiedPairs):
                    finish(moved: [], copied: copiedPairs, error: nil, restoreShelf: nil)
                case .failure(let error):
                    finish(
                        moved: [],
                        copied: [],
                        error: error.localizedDescription,
                        restoreShelf: originalItems
                    )
                }
            }
        }
    }

    private func transferShelf(forceMove: Bool) {
        let paths = shelf.map(\.path)
        guard !paths.isEmpty else {
            statusMessage = "La bandeja está vacía"
            return
        }
        guard pendingMergePreview == nil else {
            statusMessage = "Primero termina o cancela la fusión pendiente"
            return
        }
        let dest = activeWorkingPath
        let rest = offerMergeIfNeeded(paths: paths, toDirectory: dest, move: forceMove)
        if pendingMergePreview != nil {
            statusMessage = "Revisa Smart Merge; los demás elementos siguen en la bandeja"
            return
        }
        guard !rest.isEmpty else { return }
        let job = TransferQueue.Job(paths: rest, destinationDir: dest, move: forceMove)
        transferProgressFraction = 0
        transferProgressLabel = forceMove ? "Moviendo bandeja…" : "Copiando bandeja…"
        statusMessage = transferProgressLabel
        Task { @MainActor in
            do {
                let pairs = try await TransferQueue.shared.run(job) { progress in
                    Task { @MainActor in
                        self.transferProgressFraction = progress.done ? nil : progress.fraction
                        if progress.done {
                            self.transferProgressLabel = nil
                        } else {
                            self.transferProgressLabel = "\(progress.currentName) · \(progress.completed)/\(progress.total)"
                            self.statusMessage = self.transferProgressLabel
                        }
                    }
                }
                self.transferProgressFraction = nil
                self.transferProgressLabel = nil
                if forceMove {
                    self.shelf.removeAll { rest.contains($0.path) }
                    self.pushUndo(.moved(pairs: pairs))
                } else {
                    self.pushUndo(.copied(created: pairs.map(\.to)))
                }
                self.reload()
                if self.dualPaneEnabled { self.reloadSecondary() }
                self.statusMessage = forceMove
                    ? "Movidos \(pairs.count) a esta carpeta · ⌘Z deshace"
                    : "Copiados \(pairs.count) a esta carpeta · ⌘Z deshace"
            } catch {
                self.transferProgressFraction = nil
                self.transferProgressLabel = nil
                self.statusMessage = error.localizedDescription
            }
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
        guard let record = undoStack.last else {
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
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: originalParent.path, isDirectory: &isDirectory),
                          isDirectory.boolValue else { continue }
                    var destination = URL(fileURLWithPath: pair.from)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        destination = FileOps.uniqueURL(destination)
                    }
                    try FileManager.default.moveItem(at: current, to: destination)
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

            case .merged(let created, let sourceOriginalPath, let sourceTrashPath, let replacements):
                let fm = FileManager.default
                var removedCopies = 0
                var restoredBackups = 0
                var restoredSource = false

                // Quita primero los archivos nuevos para dejar libres las rutas originales.
                for path in created.reversed() {
                    let url = URL(fileURLWithPath: path)
                    guard fm.fileExists(atPath: url.path) else { continue }
                    try fm.trashItem(at: url, resultingItemURL: nil)
                    removedCopies += 1
                }

                // Restaura los archivos que fueron reemplazados desde la Papelera o respaldo oculto.
                for replacement in replacements.reversed() {
                    let backup = URL(fileURLWithPath: replacement.backupPath)
                    guard fm.fileExists(atPath: backup.path) else { continue }
                    let original = URL(fileURLWithPath: replacement.originalPath)
                    let destination = fm.fileExists(atPath: original.path) ? FileOps.uniqueURL(original) : original
                    try fm.moveItem(at: backup, to: destination)
                    restoredBackups += 1
                }

                // Si el merge fue un movimiento, devuelve también la carpeta de origen.
                if let sourceOriginalPath, let sourceTrashPath {
                    let trashedSource = URL(fileURLWithPath: sourceTrashPath)
                    if fm.fileExists(atPath: trashedSource.path) {
                        let original = URL(fileURLWithPath: sourceOriginalPath)
                        let destination = fm.fileExists(atPath: original.path) ? FileOps.uniqueURL(original) : original
                        try fm.moveItem(at: trashedSource, to: destination)
                        restoredSource = true
                    }
                }

                reload()
                statusMessage = "Smart Merge deshecho: \(removedCopies) copia(s) retiradas, \(restoredBackups) respaldo(s) restaurado(s)"
                if sourceOriginalPath != nil && !restoredSource {
                    statusMessage = (statusMessage ?? "") + " · No encontré el origen en la Papelera"
                }
            }
            undoStack.removeLast()
        } catch {
            // Conserva el registro para permitir reintentar lo que no se pudo revertir.
            statusMessage = "Deshacer quedó incompleto; puedes reintentar: \(error.localizedDescription)"
        }
    }

    /// Paths para arrastrar a Dropover / Finder / otras apps.
    func dragPaths(for entry: FileEntry) -> [String] {
        if selectedIDs.contains(entry.id), selectedIDs.count > 1 {
            return selectedEntries.map(\.path)
        }
        return [entry.path]
    }

    /// Rutas a sacar fuera de Ordena (selección del panel activo, o bandeja).
    var outboundPaths: [String] {
        let selected = activeSelectedEntries.map(\.path).filter {
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
        enqueueTransfer(paths: rest, toDirectory: dest, move: move) { result in
            switch result {
            case .success(let pairs):
                if copy {
                    self.pushUndo(.copied(created: pairs.map(\.to)))
                } else {
                    self.shelf.removeAll { rest.contains(($0.path as NSString).standardizingPath) }
                    self.selectedIDs = []
                    self.pushUndo(.moved(pairs: pairs))
                }
                self.folderDropTargetPath = nil
                self.clearArmedFileDrag()
                self.reload()
                let name = URL(fileURLWithPath: dest).lastPathComponent
                self.statusMessage = copy
                    ? "Copiados \(pairs.count) → \(name) · ⌘Z deshace"
                    : "Movidos \(pairs.count) → \(name) · ⌘Z deshace"
            case .failure(let error):
                self.statusMessage = error.localizedDescription
            }
        }
    }

    private func collectDroppedPaths(
        _ providers: [NSItemProvider],
        then: @escaping @MainActor ([String]) -> Void
    ) {
        DropPathCollector.collect(providers, typeIdentifier: "public.file-url") { collected in
            guard !collected.isEmpty else { return }
            then(collected)
        }
    }

    private func startMeasuringSizes() {
        let snapshot = entries
        let path = currentPath
        isMeasuringSizes = true
        sizeMeasurementsIncomplete = false

        measureTask = Task.detached(priority: .utility) {
            var updated = snapshot
            var total: Int64 = 0
            var incomplete = false

            for index in updated.indices {
                if Task.isCancelled { return }
                let entry = updated[index]
                let measurement = FolderSizer.measureDetailed(
                    path: entry.path,
                    isDirectory: entry.isDirectory
                )
                if !measurement.isComplete { incomplete = true }
                let bytes = measurement.bytes
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
            let folderMeasurement = FolderSizer.measureDirectoryDetailed(at: path)
            if !folderMeasurement.isComplete { incomplete = true }

            await MainActor.run {
                guard self.currentPath == path else { return }
                self.entries = updated
                self.folderTotalBytes = max(folderMeasurement.bytes, total)
                self.sizeMeasurementsIncomplete = incomplete
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

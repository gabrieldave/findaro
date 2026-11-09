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
    private var userDidNavigateSecondary = false
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

    // MARK: Licencia y Paywall
    @Published var showLicenseSheet = false

    @discardableResult
    public func ensureLicenseAllowsWrite() -> Bool {
        if LicenseStore.shared.state.isUsable && LicenseGate.allowsWrite() {
            return true
        }
        statusMessage = L10n.s(
            "Función bloqueada: el período de prueba ha finalizado. Adquiere una licencia Pro.",
            "Feature blocked: the trial period has expired. Please purchase a Pro license."
        )
        showLicenseSheet = true
        return false
    }

    // MARK: Smart merge
    @Published var pendingMergePreview: FolderMerge.Preview?
    @Published var pendingMergeMove = false

    // MARK: Asistente
    @Published var showAssistantPanel = false
    @Published var isAssistantFocused = false
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
            statusMessage = L10n.s("Findaro ya está como app de carpetas", "Findaro is already the default folder app")
        case .readyForOpenWith:
            statusMessage = L10n.s("Findaro lista en «Abrir con» — falta elegir Siempre (límite de Apple)", "Findaro listed in «Open With» — select Always (Apple requirement)")
        case .appMissing:
            statusMessage = L10n.s("No encuentro Findaro.app en Aplicaciones", "Could not find Findaro.app in Applications")
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
    private var shelfCancellable: AnyCancellable?
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
        L10n.activeLanguage = store.preferences.appLanguage
        UserDefaults.standard.set(store.preferences.appLanguage.rawValue, forKey: "findaro_app_language")
        self.columnPaths = [start]
        self.secondaryPath = start
        OllamaClient.shared.applyPreferences(store.preferences)
        OllamaClient.shared.onModelAutoSelected = { [weak self] model in
            self?.store.update { $0.ollamaModel = model }
        }
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
        LicenseGate.setWriteAllowed(LicenseStore.shared.state.isUsable) { [weak self] in
            Task { @MainActor in
                self?.showLicenseSheet = true
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

        shelfCancellable = NotificationCenter.default
            .publisher(for: SharedShelf.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if (note.object as? BrowserModel) !== self {
                    self.shelf = SharedShelf.shared.items
                }
            }
    }

    private func handlePreferencesDidChange(_ note: Notification) {
        self.store.reloadFromDisk()
        let prefs = self.store.preferences
        L10n.activeLanguage = prefs.appLanguage
        UserDefaults.standard.set(prefs.appLanguage.rawValue, forKey: "findaro_app_language")
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
        statusMessage = L10n.s("Orden normal de la carpeta", "Standard folder sort order")
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
            statusMessage = L10n.s("Carpeta actualizada", "Folder refreshed")
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
            statusMessage = L10n.s("Panel destino actualizado", "Destination pane refreshed")
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
        isAssistantFocused = false
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
        isAssistantFocused = false
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
                ? L10n.s(
                    "Destino listo para mover — ⌘+clic / arrastra a Origen · Esc cancela",
                    "Destination ready to move — ⌘+click / drag to Origin · Esc cancels"
                )
                : L10n.s(
                    "Destino · \(fileDragArmedPaths.count) listos — arrastra a Origen · Esc",
                    "Destination · \(fileDragArmedPaths.count) ready — drag to Origin · Esc"
                )
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
            ? L10n.s(
                "Listo para mover — ⌘+clic siguiente = mismo rango que ⇧ · Esc cancela",
                "Ready to move — ⌘+click next extends range · Esc cancels"
            )
            : L10n.s(
                "\(fileDragArmedPaths.count) listos — ⌘+clic = igual que ⇧ · arrastra · Esc",
                "\(fileDragArmedPaths.count) ready — ⌘+click extends range · drag · Esc"
            )
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
            statusMessage = L10n.s("Abrí carpeta: \(entry.name)", "Opened folder: \(entry.name)")
        } else if ArchiveOps.isExtractable(entry.path) {
            // open() pone el estado (descomprimiendo / listo); no pisar con «Abrí:».
            open(entry)
        } else {
            open(entry)
            statusMessage = L10n.s("Abrí: \(entry.name)", "Opened: \(entry.name)")
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
            return "\(categoryFilter.labelLocalized) · \(n)"
        }
        return "\(L10n.s("Todos", "All")) · \(entries.count)"
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
            return "\(L10n.s("Atajo", "Shortcut")) · \(shortcut.displayTitle) · \(visibleEntries.count)"
        }
        if downloadsTodayMode {
            return L10n.s("Descargados hoy · \(downloadsTodayCount) en esta carpeta", "Downloaded today · \(downloadsTodayCount) in this folder")
        }
        return rule.summaryLocalized
    }

    var hasFolderOverride: Bool {
        store.preferences.hasOverride(for: currentPath)
    }

    var scopeBadge: String {
        if downloadsTodayMode {
            return L10n.s("Modo exclusivo · orden normal en pausa", "Exclusive mode · normal sort paused")
        }
        return hasFolderOverride ? L10n.s("Solo esta carpeta", "This folder only") : L10n.s("Default global", "Global default")
    }

    var folderTotalLabel: String {
        if isMeasuringSizes && folderTotalBytes == 0 {
            return L10n.s("Midiendo peso…", "Calculating size…")
        }
        return sizeMeasurementsIncomplete
            ? L10n.s("Carpeta: ≥ \(FolderSizer.format(folderTotalBytes))", "Folder: ≥ \(FolderSizer.format(folderTotalBytes))")
            : L10n.s("Carpeta: \(FolderSizer.format(folderTotalBytes))", "Folder: \(FolderSizer.format(folderTotalBytes))")
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
        isAssistantFocused = false
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
        statusMessage = L10n.s("Nada seleccionado", "Nothing selected")
    }

    func clearSecondarySelection() {
        secondarySelectedIDs = []
        secondarySelectionAnchorID = nil
        secondarySelectionFocusID = nil
        statusMessage = L10n.s("Nada seleccionado (Destino)", "Nothing selected (Destination)")
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
        statusMessage = L10n.s("Selección cancelada", "Selection cleared")
    }

    /// Clic en zona vacía: no cancelar si hay ⌘/⇧ (evita apagar el naranja al soltar ⌘+clic).
    /// En doble panel también enfoca el panel donde se hizo clic.
    func cancelSelectionFromBackgroundTap(activating pane: PaneFocus? = nil) {
        isAssistantFocused = false
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
            statusMessage = L10n.s("Nada seleccionado", "Nothing selected")
        } else if n == 1, let name = selectedEntries.first?.name {
            statusMessage = L10n.s("1 seleccionado — \(name)", "1 selected — \(name)")
        } else {
            statusMessage = L10n.s("\(n) seleccionados", "\(n) selected")
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
            if !userDidNavigateSecondary || secondaryPath.isEmpty {
                secondaryPath = currentPath
            }
            focusedPane = .secondary
            reloadSecondary()
            statusMessage = L10n.s(
                "Dos paneles: izquierda origen · derecha destino. Arrastra o «Mover →»",
                "Dual pane: left source · right destination. Drag or «Move →»"
            )
        } else {
            secondaryFolderWatcher.stop()
            focusedPane = .primary
            statusMessage = L10n.s("Un panel", "Single pane")
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
            ? L10n.s("Panel Origen activo · Tab cambia · ⌘⇧→ Destino", "Origin pane active · Tab switches · ⌘⇧→ Destination")
            : L10n.s("Panel Destino activo · Tab cambia · ⌘⇧← Origen", "Destination pane active · Tab switches · ⌘⇧← Origin")
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
            secondaryError = L10n.s("No es una carpeta", "Not a folder")
            return
        }
        secondaryPath = target
        userDidNavigateSecondary = true
        secondarySelectedIDs = []
        secondarySelectionAnchorID = nil
        secondarySelectionFocusID = nil
        focusedPane = .secondary
        reloadSecondary()
        statusMessage = L10n.s("Panel derecho: \((target as NSString).lastPathComponent)", "Right pane: \((target as NSString).lastPathComponent)")
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
            statusMessage = L10n.s("No hay carpetas distintas para intercambiar", "No distinct folders to swap")
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
        statusMessage = L10n.s("Paneles intercambiados", "Panes swapped")
    }

    func selectSecondaryOnly(_ id: String) {
        isAssistantFocused = false
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
        isAssistantFocused = false
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
            statusMessage = L10n.s("Nada seleccionado (Destino)", "Nothing selected (Destination)")
        } else if n == 1, let name = secondarySelectedEntries.first?.name {
            statusMessage = L10n.s("Destino · 1 seleccionado — \(name)", "Destination · 1 selected — \(name)")
        } else {
            statusMessage = L10n.s("Destino · \(n) seleccionados", "Destination · \(n) selected")
        }
    }

    func openSecondaryEntry(_ entry: FileEntry) {
        if entry.isDirectory {
            navigateSecondary(to: entry.path)
        } else if isDiskImage(entry.path) {
            openDiskImage(entry, inSecondary: true)
        } else if ArchiveOps.isExtractable(entry.path) {
            extractArchive(entry, intoSecondary: true)
        } else {
            openFileWithSystem(entry)
        }
    }

    /// Mueve (o copia) la selección del panel izquierdo al derecho.
    func transferPrimarySelectionToSecondary(copy: Bool = false) {
        guard dualPaneEnabled else { return }
        let paths = selectedEntries.map(\.path)
        guard !paths.isEmpty else {
            let verb = copy ? L10n.s("copiar", "copy") : L10n.s("mover", "move")
            statusMessage = secondarySelectedIDs.isEmpty
                ? L10n.s("Para \(verb) a Destino, selecciona algo en Origen (izquierda)", "To \(verb) to Destination, select items in Origin (left)")
                : L10n.s("Esa selección está en Destino. Usa «← Mover» o selecciona en Origen", "That selection is in Destination. Use «← Move» or select in Origin")
            return
        }
        _ = transferPaths(paths, toDirectory: secondaryPath, copy: copy, clearPrimary: true, clearSecondary: false)
    }

    /// Mueve (o copia) la selección del panel derecho al izquierdo (Origen).
    func transferSecondarySelectionToPrimary(copy: Bool = false) {
        guard dualPaneEnabled else { return }
        let paths = secondarySelectedEntries.map(\.path)
        guard !paths.isEmpty else {
            let verb = copy ? L10n.s("copiar", "copy") : L10n.s("mover", "move")
            statusMessage = selectedIDs.isEmpty
                ? L10n.s("Para \(verb) a Origen, selecciona algo en Destino (derecha)", "To \(verb) to Origin, select items in Destination (right)")
                : L10n.s("Esa selección está en Origen. Usa «Mover →» o selecciona en Destino", "That selection is in Origin. Use «Move →» or select in Destination")
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
        guard ensureLicenseAllowsWrite() else { return false }
        guard dualPaneEnabled, !paths.isEmpty else { return false }
        guard pendingMergePreview == nil else {
            statusMessage = L10n.s("Primero termina o cancela la fusión pendiente", "Complete or cancel the pending merge first")
            return false
        }
        guard AgentPolicy.isPathAllowed(dest) else {
            statusMessage = L10n.s("Destino no permitido (solo tu carpeta de usuario, /Users/Shared o discos en /Volumes)", "Destination not allowed (only home folder, /Users/Shared or disks in /Volumes)")
            return false
        }
        let destStd = (dest as NSString).standardizingPath
        let filtered = paths.filter { ($0 as NSString).deletingLastPathComponent != destStd }
        guard !filtered.isEmpty else {
            statusMessage = L10n.s("Ya están en esa carpeta", "Already in that folder")
            return false
        }
        let transferPaths = offerMergeIfNeeded(paths: filtered, toDirectory: destStd, move: !copy)
        if pendingMergePreview != nil {
            statusMessage = L10n.s("Revisa Smart Merge antes de continuar con los demás elementos", "Review Smart Merge before continuing with other items")
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
                let verb = copy ? L10n.s("Copié", "Copied") : L10n.s("Moví", "Moved")
                let short = (destStd as NSString).lastPathComponent
                self.statusMessage = pairs.count == 1
                    ? L10n.s("\(verb) 1 ítem → \(short)", "\(verb) 1 item → \(short)")
                    : L10n.s("\(verb) \(pairs.count) ítems → \(short)", "\(verb) \(pairs.count) items → \(short)")
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

    // MARK: - Ir a carpeta o archivo (⌘3)

    func promptGoToFolder() {
        goToFolderDraft = currentPath
        showGoToFolderDialog = true
    }

    func submitGoToFolder() {
        var raw = goToFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        // Si viene con prefijo file://
        if raw.hasPrefix("file://") {
            if let fileUrl = URL(string: raw), fileUrl.isFileURL {
                raw = fileUrl.path
            } else {
                raw = String(raw.dropFirst(7))
            }
        }

        // Si viene entre comillas
        if (raw.hasPrefix("\"") && raw.hasSuffix("\"")) || (raw.hasPrefix("'") && raw.hasSuffix("'")) {
            raw = String(raw.dropFirst().dropLast())
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = []

        if raw == "~" {
            candidates.append(home)
        } else if raw.hasPrefix("~/") {
            candidates.append((home as NSString).appendingPathComponent(String(raw.dropFirst(2))))
        } else if raw.hasPrefix("/") {
            candidates.append(raw)
        } else {
            // 1. Relativo a la carpeta actual si existe
            candidates.append((currentPath as NSString).appendingPathComponent(raw))
            // 2. Relativo al Home del usuario (ej: Downloads/..., Desktop/...)
            candidates.append((home as NSString).appendingPathComponent(raw))
            // 3. Si el usuario pegó y se recortó el prefijo de usuario (ej. "ai/Downloads/..." o "davidai/Downloads/...")
            let username = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
            if raw.hasPrefix(username + "/") {
                let sub = String(raw.dropFirst(username.count + 1))
                candidates.append((home as NSString).appendingPathComponent(sub))
            } else if username.hasSuffix("ai") && raw.hasPrefix("ai/") {
                let sub = String(raw.dropFirst(3))
                candidates.append((home as NSString).appendingPathComponent(sub))
            }
            candidates.append(raw)
        }

        var resolvedPath: String?
        var isDir: ObjCBool = false
        for candidate in candidates {
            let std = (candidate as NSString).standardizingPath
            var d: ObjCBool = false
            if FileManager.default.fileExists(atPath: std, isDirectory: &d) {
                resolvedPath = std
                isDir = d
                break
            }
        }

        guard let path = resolvedPath else {
            statusMessage = L10n.s("No existe esa ruta o archivo", "No such folder or file exists")
            return
        }

        showGoToFolderDialog = false

        if isDir.boolValue {
            navigate(to: path)
            statusMessage = L10n.s("Fui a «\(URL(fileURLWithPath: path).lastPathComponent)»", "Navigated to «\(URL(fileURLWithPath: path).lastPathComponent)»")
        } else {
            // Es un archivo: abrirlo de inmediato con su app predeterminada
            let parentDir = (path as NSString).deletingLastPathComponent
            let current = (currentPath as NSString).standardizingPath
            if parentDir != current {
                navigate(to: parentDir)
            }
            selectOnly(path)

            let fileURL = URL(fileURLWithPath: path)
            if NSWorkspace.shared.open(fileURL) {
                statusMessage = L10n.s("Abrí «\(fileURL.lastPathComponent)»", "Opened «\(fileURL.lastPathComponent)»")
            } else {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                proc.arguments = [path]
                do {
                    try proc.run()
                    statusMessage = L10n.s("Abrí «\(fileURL.lastPathComponent)»", "Opened «\(fileURL.lastPathComponent)»")
                } catch {
                    statusMessage = L10n.s("No se pudo abrir «\(fileURL.lastPathComponent)»: \(error.localizedDescription)", "Could not open «\(fileURL.lastPathComponent)»: \(error.localizedDescription)")
                }
            }
        }
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
            ? L10n.s("Buscando «\(q)» en nombres, libros/PDFs y fotos (OCR)…", "Searching «\(q)» in filenames, books/PDFs and photos (OCR)…")
            : L10n.s("Buscando «\(q)» en subcarpetas…", "Searching «\(q)» in subfolders…")
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
                                ? L10n.s("Sin coincidencias para «\(q)»", "No matches for «\(q)»")
                                : L10n.s("\(progress.matched) resultados para «\(q)»", "\(progress.matched) results for «\(q)»")
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
        statusMessage = L10n.s("Saliste de la búsqueda · orden normal de la carpeta", "Exited search · standard folder sort")
    }

    func openDeepSearchHit(_ hit: SearchHit) {
        let path = (hit.path as NSString).standardizingPath
        if hit.isDirectory {
            clearFiltersForReveal()
            navigate(to: path)
            statusMessage = L10n.s("Abrí carpeta: \((path as NSString).lastPathComponent)", "Opened folder: \((path as NSString).lastPathComponent)")
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
            statusMessage = L10n.s("Seleccionado: \((path as NSString).lastPathComponent)", "Selected: \((path as NSString).lastPathComponent)")
        } else {
            statusMessage = L10n.s("Abrí la carpeta, pero no veo ese archivo en la lista", "Opened folder, but file is not visible in list")
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
        guard ensureLicenseAllowsWrite() else { return }
        guard let preview = pendingMergePreview else { return }
        let asMove = pendingMergeMove
        let sourcePath = preview.sourcePath
        let destPath = preview.destPath
        statusMessage = L10n.s("Fusionando…", "Merging…")
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
                            self.statusMessage = L10n.s(
                                "Fusioné los archivos, pero conservé el origen porque no pude enviarlo con seguridad a la Papelera: \(error.localizedDescription)",
                                "Merged files, but kept original folder because it could not be safely sent to Trash: \(error.localizedDescription)"
                            )
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
                            ? L10n.s("Fusionado reemplazando · origen a Papelera → \(name) · ⌘Z puede restaurar", "Merged replacing conflicts · source to Trash → \(name) · ⌘Z can restore")
                            : L10n.s("Fusionado reemplazando conflictos → \(name) · ⌘Z puede restaurar", "Merged replacing conflicts → \(name) · ⌘Z can restore")
                    } else {
                        self.statusMessage = asMove
                            ? L10n.s("Fusionado y origen a Papelera → \(name) · ⌘Z deshace", "Merged and source to Trash → \(name) · ⌘Z undoes")
                            : L10n.s("Fusionado → \(name) · ⌘Z deshace", "Merged → \(name) · ⌘Z undoes")
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
        guard ensureLicenseAllowsWrite() else { return [] }
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
            statusMessage = L10n.s("Comparando carpetas (Smart Merge)…", "Comparing folders (Smart Merge)…")
            let source = merge.source
            let destFolder = merge.dest
            Task {
                let preview = await Task.detached(priority: .userInitiated) {
                    FolderMerge.preview(source: source, dest: destFolder)
                }.value
                await MainActor.run {
                    self.pendingMergePreview = preview
                    self.statusMessage = L10n.s("Revisa la fusión antes de tocar el destino", "Review merge before modifying destination")
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
            ? L10n.s("Listo: actualicé esta carpeta. Hay 1 elemento.", "Done: refreshed this folder. 1 item found.")
            : L10n.s("Listo: actualicé esta carpeta. Hay \(n) elementos.", "Done: refreshed this folder. \(n) items found.")
        appendAgentReply(msg)
        showAssistantPanel = true
    }

    /// Abre Terminal.app en la carpeta del panel activo (Origen o Destino).
    func openTerminalHere() {
        let path = (activeWorkingPath as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            statusMessage = L10n.s("No hay carpeta para Terminal", "No folder selected for Terminal")
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
                        self.statusMessage = L10n.s("No pude abrir Terminal: \(error.localizedDescription)", "Could not open Terminal: \(error.localizedDescription)")
                    } else {
                        self.statusMessage = L10n.s("Terminal en \((path as NSString).lastPathComponent)", "Terminal in \((path as NSString).lastPathComponent)")
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
            statusMessage = L10n.s("Terminal en \((path as NSString).lastPathComponent)", "Terminal in \((path as NSString).lastPathComponent)")
        } catch {
            statusMessage = L10n.s("No pude abrir Terminal", "Could not open Terminal")
        }
    }

    func runAssistant(prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !agentBusy else {
            appendAgentReply(
                L10n.s(
                    "Todavía estoy con el pedido anterior. Espera un momento…",
                    "Still working on the previous request. Please wait a moment…"
                ),
                alsoStatus: true
            )
            return
        }
        showAssistantPanel = true
        agentBusy = true
        agentProgressLabel = OllamaClient.shared.isReady
            ? L10n.s("Consultando Ollama («\(OllamaClient.shared.selectedModel)»)", "Querying Ollama («\(OllamaClient.shared.selectedModel)»)")
            : L10n.s("Interpretando con reglas", "Interpreting with rules")
        statusMessage = agentProgressLabel + "…"
        defer {
            agentBusy = false
            agentProgressLabel = ""
        }
        // Pinta banner + puntitos antes de cualquier trabajo pesado.
        await Task.yield()

        appendAgentUser(trimmed)
        agentLog.append("> \(trimmed)")

        // Saludos y preguntas frecuentes: respuesta instantánea sin carga de GPU.
        let lower = trimmed.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters)
        let greetings: Set<String> = [
            "hola", "buen dia", "buenos dias", "buenas", "buenas tardes", "buenas noches",
            "hey", "saludos", "hi", "hello", "ayuda", "que puedes hacer", "¿que puedes hacer?", "como te uso"
        ]
        if greetings.contains(lower) {
            appendAgentReply(
                L10n.s("¡Hola! Soy Findaro. Puedo ayudarte a buscar archivos (ej: «busca fotos de ayer»), ver qué carpetas pesan más («qué pesa más»), organizar tus descargas («organizar descargas») o detectar duplicados. ¿Qué deseas hacer?", "Hi! I am Findaro. I can help you search files (e.g., «find yesterday’s photos»), see which folders are heaviest («what’s largest»), organize your downloads («clean up downloads»), or detect duplicates. What would you like to do?"),
                alsoStatus: true
            )
            return
        }

        if let shortcut = matchAssistantShortcut(prompt: trimmed) {
            applyAssistantShortcut(shortcut)
            return
        }

        let ollama = OllamaClient.shared
        if ollama.isReady {
            agentProgressLabel = L10n.s("Consultando Ollama («\(ollama.selectedModel)»)", "Querying Ollama («\(ollama.selectedModel)»)")
            statusMessage = agentProgressLabel + "…"
            await Task.yield()
            switch await ollama.proposePlan(prompt: trimmed, currentPath: currentPath) {
            case .plan(let llm):
                agentProgressLabel = L10n.s("Aplicando plan de Ollama", "Applying Ollama plan")
                await Task.yield()
                agentPlan = enrichAgentPlan(llm)
                agentLog.append("Plan (Ollama): \(llm.summary)")
            case .message(let text):
                agentProgressLabel = ""
                await Task.yield()
                appendAgentReply(text, alsoStatus: true)
                return
            case .unavailable:
                agentProgressLabel = L10n.s("Ollama no disponible · reglas", "Ollama unavailable · fallback to rules")
                await Task.yield()
                let plan = AgentIntentParser.plan(from: trimmed, currentPath: currentPath)
                agentPlan = enrichAgentPlan(plan)
                agentLog.append("Plan (reglas): \(plan.summary)")
            case .failed(let reason):
                agentProgressLabel = L10n.s("Ollama falló · usando reglas", "Ollama failed · fallback to rules")
                await Task.yield()
                appendAgentReply(
                    L10n.s("Ollama no contestó a tiempo (\(reason)). Sigo con reglas locales.", "Ollama did not respond in time (\(reason)). Continuing with local rules."),
                    alsoStatus: true
                )
                let plan = AgentIntentParser.plan(from: trimmed, currentPath: currentPath)
                agentPlan = enrichAgentPlan(plan)
                agentLog.append("Plan (reglas tras fallo Ollama): \(plan.summary)")
            }
        } else {
            agentProgressLabel = L10n.s("Interpretando con reglas", "Parsing with local rules")
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
                    plan.prompt.lowercased().contains("organiza") || plan.prompt.lowercased().contains("clean")
                        ? L10n.s("No hay archivos sueltos para organizar por tipo en esta carpeta.", "No loose files to organize by type in this folder.")
                        : L10n.s("No hay nada que hacer con ese pedido en esta carpeta.", "Nothing to execute for this request in this folder.")
                )
                agentPlan = nil
            } else if let block = validateWritePlan(plan) {
                appendAgentReply(block)
                agentPlan = nil
                pendingAgentApproval = nil
            } else {
                pendingAgentApproval = plan
                appendAgentReply(
                    L10n.s("Esto va a modificar archivos. Revisa el plan y dale a Aprobar si estás de acuerdo.", "This will modify files. Review the plan and click Approve if you agree."),
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
                    return L10n.s("Dime el destino, por ejemplo: «mueve a Facturas» o «copia a Documentos».", "Tell me the destination, for example: «move to Invoices» or «copy to Documents».")
                }
                if step.pathsArgument.isEmpty {
                    return L10n.s("Selecciona primero los archivos en la lista y vuelve a pedirlo.", "Select files in the list first, then ask again.")
                }
                guard AgentPolicy.isPathAllowed(destination),
                      AgentPolicy.isPathWithinScope(destination, root: currentPath),
                      step.pathsArgument.allSatisfy({
                          AgentPolicy.isPathAllowed($0) && AgentPolicy.isPathWithinScope($0, root: currentPath)
                      }) else {
                    return L10n.s(
                        "El plan incluye una ruta fuera de la carpeta actual o de sus subcarpetas. Navega a esa carpeta y vuelve a intentarlo.",
                        "The plan targets a path outside the current folder or subfolders. Navigate to that folder and try again."
                    )
                }
            case .createDirectory:
                let name = (step.arguments["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let parent = step.arguments["parent"] ?? currentPath
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                    return L10n.s("El nombre de la carpeta debe ser un solo nombre, sin rutas ni «..».", "The folder name must be a single name without paths or «..».")
                }
                guard AgentPolicy.isPathAllowed(parent),
                      AgentPolicy.isPathWithinScope(parent, root: currentPath) else {
                    return L10n.s("No puedo crear esa carpeta fuera de la carpeta actual.", "Cannot create that folder outside current folder.")
                }
            case .renameFiles:
                let newName = step.arguments["newName"] ?? ""
                let path = step.arguments["path"] ?? step.pathsArgument.first ?? ""
                if newName.isEmpty || path.isEmpty {
                    return L10n.s("Selecciona un archivo o carpeta y di «renombra a nombre-nuevo».", "Select a file or folder and say «rename to new-name».")
                }
                guard AgentPolicy.isPathAllowed(path),
                      AgentPolicy.isPathWithinScope(path, root: currentPath) else {
                    return L10n.s("No puedo renombrar elementos fuera de la carpeta actual.", "Cannot rename items outside current folder.")
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
            let folderName = category.organizeFolderNameLocalized
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
            appendAgentReply(L10n.s("Esperando tu aprobación para seguir.", "Waiting for your approval to proceed."), alsoStatus: true)
            return
        }
        for step in plan.steps {
            switch step.name {
            case .searchFiles:
                let q = step.arguments["query"] ?? plan.prompt
                startDeepSearch(query: q, includeContent: false)
                appendAgentReply(
                    L10n.s("Busco archivos cuyo nombre coincida con «\(q)» en esta carpeta y subcarpetas. Mira la lista o el filtro de búsqueda.", "Searching files matching «\(q)» in this folder and subfolders. Check the list or search filter.")
                )
            case .searchContent:
                let q = step.arguments["query"] ?? plan.prompt
                startDeepSearch(query: q, includeContent: true)
                appendAgentReply(
                    L10n.s("Busco «\(q)» en nombres, libros/PDFs y dentro de imágenes (OCR) de esta carpeta y abajo.", "Searching «\(q)» in filenames, documents/PDFs, and inside images (OCR) in this folder and below.")
                )
            case .listDirectory:
                reload()
                let n = visibleEntries.count
                appendAgentReply(
                    n == 0
                        ? L10n.s("Esta carpeta está vacía (o no pude listar nada).", "This folder is empty (or could not be listed).")
                        : L10n.s("Aquí hay \(n) elementos. La lista del centro está al día.", "Found \(n) items here. The file list is up to date.")
                )
            case .getStorageUsage:
                showHeaviestForCleanup()
                appendAgentReply(
                    L10n.s("Ordené por peso: lo más pesado arriba. Arriba del todo verás el Top peso con los que más ocupan.", "Sorted by size: largest items on top. Top sizes are displayed in the header.")
                )
            case .findDuplicates:
                let dups = findDuplicateCandidates()
                if dups == 0 {
                    appendAgentReply(
                        L10n.s("No encontré duplicados obvios aquí (mismo nombre y mismo tamaño). Si hay copias con otro nombre, aún no las detecto.", "No obvious duplicates found here (same name and size).")
                    )
                } else {
                    appendAgentReply(
                        dups == 1
                            ? L10n.s("Encontré 1 grupo posible de duplicados y lo marqué en la lista.", "Found 1 possible duplicate group and selected it.")
                            : L10n.s("Encontré \(dups) grupos posibles de duplicados. Marqué el primero en la lista.", "Found \(dups) possible duplicate groups. Selected the first group in list.")
                    )
                }
            case .organizeFiles:
                // Ya se expandió en enrichAgentPlan; si llega aquí, no había archivos.
                appendAgentReply(L10n.s("No encontré archivos sueltos para organizar por tipo aquí.", "No loose files found to organize by type here."))
            case .openFile:
                if let p = step.arguments["path"], let entry = entries.first(where: { $0.path == p }) {
                    open(entry)
                    appendAgentReply(L10n.s("Abrí «\(entry.name)». ", "Opened «\(entry.name)». "))
                } else {
                    appendAgentReply(L10n.s("No pude abrir ese archivo: no está en la carpeta actual.", "Could not open that file: it is not in the current folder."))
                }
            case .previewFile:
                quickLookSelection()
                appendAgentReply(L10n.s("Abrí Vista rápida de la selección.", "Opened Quick Look for selection."))
            case .getFileMetadata:
                if let p = step.arguments["path"], let entry = entries.first(where: { $0.path == p }) {
                    showInfo(entry)
                    appendAgentReply(L10n.s("Mostré la info de «\(entry.name)». ", "Showing info for «\(entry.name)». "))
                } else if let entry = selectedEntries.first {
                    showInfo(entry)
                    appendAgentReply(L10n.s("Mostré la info de la selección.", "Showing info for selection."))
                } else {
                    appendAgentReply(L10n.s("No hay nada seleccionado para mostrar info.", "Nothing selected to show info."))
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
        guard ensureLicenseAllowsWrite() else { return }
        let name = (step.arguments["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = step.arguments["parent"] ?? currentPath
        guard !name.isEmpty else {
            appendAgentReply(L10n.s("No me diste nombre para la carpeta.", "No folder name provided."))
            return
        }
        guard AgentPolicy.isPathAllowed(parent),
              AgentPolicy.isPathWithinScope(parent, root: currentPath),
              name != ".", name != "..", !name.contains("/") else {
            appendAgentReply(L10n.s("La ruta o el nombre de la carpeta no están permitidos.", "The folder path or name is not allowed."))
            return
        }
        // Si ya existe (p. ej. al organizar), reutilízala.
        let existing = (parent as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: existing) {
            appendAgentReply(L10n.s("La carpeta «\(name)» ya estaba; la reutilizo.", "Folder «\(name)» already existed; reusing it."))
            return
        }
        do {
            let created = try FileOps.createFolder(named: name, in: parent)
            pushUndo(.copied(created: [created])) // deshacer = papelera de la carpeta nueva vacía/casi
            if parent == currentPath { reload() }
            appendAgentReply(L10n.s("Creé la carpeta «\((created as NSString).lastPathComponent)».", "Created folder «\((created as NSString).lastPathComponent)»."))
        } catch {
            appendAgentReply(L10n.s("No pude crear la carpeta: \(error.localizedDescription)", "Could not create folder: \(error.localizedDescription)"))
        }
    }

    private func executeTransfer(_ step: AgentToolCall, move: Bool) {
        guard ensureLicenseAllowsWrite() else { return }
        let paths = step.pathsArgument
        let dest = (step.arguments["destination"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paths.isEmpty else {
            appendAgentReply(
                move
                    ? L10n.s("Selecciona algo y di p. ej. «mueve a Facturas».", "Select items and say e.g. «move to Invoices».")
                    : L10n.s("Selecciona algo y di p. ej. «copia a Facturas».", "Select items and say e.g. «copy to Invoices».")
            )
            return
        }
        guard !dest.isEmpty else {
            appendAgentReply(L10n.s("Falta el destino. Prueba «mueve a NombreCarpeta».", "Destination missing. Try «move to FolderName»."))
            return
        }
        guard AgentPolicy.isPathAllowed(dest),
              AgentPolicy.isPathWithinScope(dest, root: currentPath),
              paths.allSatisfy({
                  AgentPolicy.isPathAllowed($0) && AgentPolicy.isPathWithinScope($0, root: currentPath)
              }) else {
            appendAgentReply(L10n.s("Alguna ruta está fuera de la carpeta actual o no está permitida.", "A path is outside current folder or not allowed."))
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
                appendAgentReply(L10n.s("No pude preparar el destino: \(error.localizedDescription)", "Could not prepare destination: \(error.localizedDescription)"))
                return
            }
        }
        guard destIsDir.boolValue || FileManager.default.fileExists(atPath: dest) else {
            appendAgentReply(L10n.s("El destino no es una carpeta.", "Destination is not a folder."))
            return
        }
        // Si dest es archivo (raro), abortar.
        var check: ObjCBool = false
        FileManager.default.fileExists(atPath: dest, isDirectory: &check)
        guard check.boolValue else {
            appendAgentReply(L10n.s("El destino tiene que ser una carpeta.", "Destination must be a folder."))
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
                let verb = move ? L10n.s("Moví", "Moved") : L10n.s("Copié", "Copied")
                let destName = (dest as NSString).lastPathComponent
                self.appendAgentReply(
                    pairs.count == 1
                        ? L10n.s("\(verb) 1 ítem a «\(destName)».", "\(verb) 1 item to «\(destName)».")
                        : L10n.s("\(verb) \(pairs.count) ítems a «\(destName)».", "\(verb) \(pairs.count) items to «\(destName)».")
                )
            case .failure(let error):
                let actionVerb = move ? L10n.s("mover", "move") : L10n.s("copiar", "copy")
                self.appendAgentReply(L10n.s("No pude \(actionVerb): \(error.localizedDescription)", "Could not \(actionVerb): \(error.localizedDescription)"))
            }
        }
    }

    private func executeRename(_ step: AgentToolCall) {
        guard ensureLicenseAllowsWrite() else { return }
        let newName = (step.arguments["newName"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let path = step.arguments["path"] ?? step.pathsArgument.first ?? selectedEntries.first?.path
        guard let path, !newName.isEmpty else {
            appendAgentReply(L10n.s("Selecciona un ítem y di «renombra a nombre-nuevo».", "Select an item and say «rename to new-name»."))
            return
        }
        guard AgentPolicy.isPathAllowed(path),
              AgentPolicy.isPathWithinScope(path, root: currentPath) else {
            appendAgentReply(L10n.s("Esa ruta está fuera de la carpeta actual o no está permitida.", "That path is outside current folder or not allowed."))
            return
        }
        do {
            let newPath = try FileOps.rename(path: path, to: newName)
            pushUndo(.moved(pairs: [.init(from: path, to: newPath)]))
            reload()
            selectOnly(newPath)
            appendAgentReply(L10n.s("Renombré a «\(newName)».", "Renamed to «\(newName)»."))
        } catch {
            appendAgentReply(L10n.s("No pude renombrar: \(error.localizedDescription)", "Could not rename: \(error.localizedDescription)"))
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
            ? L10n.s("Sin duplicados obvios aquí", "No obvious duplicates here")
            : L10n.s("\(groups.count) grupos posibles (nombre+tamaño)", "\(groups.count) possible duplicate groups (name+size)")
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
        statusMessage = on ? L10n.s("Mostrando ocultos", "Showing hidden files") : L10n.s("Ocultos escondidos", "Hidden files hidden")
    }

    func toggleShowHiddenFiles() {
        setShowHiddenFiles(!showHiddenFiles)
    }

    func setFlattenFolderView(_ on: Bool) {
        flattenFolderView = on
        store.update { $0.flattenFolderView = on }
        reload(preserveSelection: true)
        if dualPaneEnabled { reloadSecondary(preserveSelection: true) }
        statusMessage = on ? L10n.s("Vista plana (archivos anidados)", "Flat view (nested files)") : L10n.s("Vista de carpeta", "Folder view")
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
            statusMessage = L10n.s("Atrás", "Back")
            refreshHistoryFlags()
            return
        }
        if canNavigateUp {
            goUp()
            statusMessage = L10n.s("Atrás · carpeta superior", "Back · parent folder")
            return
        }
        statusMessage = L10n.s("No hay carpeta anterior", "No previous folder")
        refreshHistoryFlags()
    }

    /// Como Alt+→ en Windows / ⌘] en Finder.
    func goForward() {
        guard let next = forwardStack.popLast() else {
            statusMessage = L10n.s("No hay carpeta siguiente", "No next folder")
            refreshHistoryFlags()
            return
        }
        backStack.append(currentPath)
        navigate(to: next, recordHistory: false)
        statusMessage = L10n.s("Adelante", "Forward")
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
            statusMessage = L10n.s("Solo se pueden favoritar carpetas", "Only folders can be added to Favorites")
            return
        }
        let standardized = (path as NSString).standardizingPath
        if isFavorite(standardized) {
            statusMessage = L10n.s("Ya está en Favoritos", "Already in Favorites")
            return
        }
        store.update { $0.favorites.append(standardized) }
        objectWillChange.send()
        statusMessage = L10n.s("Favorito: \(URL(fileURLWithPath: standardized).lastPathComponent)", "Favorite: \(URL(fileURLWithPath: standardized).lastPathComponent)")
    }

    func removeFavorite(_ path: String) {
        let target = (path as NSString).standardizingPath
        store.update { prefs in
            prefs.favorites.removeAll { ($0 as NSString).standardizingPath == target }
        }
        objectWillChange.send()
        statusMessage = L10n.s("Quitado de Favoritos", "Removed from Favorites")
    }

    func moveFavorite(path: String, direction: Int) {
        let target = (path as NSString).standardizingPath
        guard let index = store.preferences.favorites.firstIndex(where: { ($0 as NSString).standardizingPath == target }) else { return }
        let newIndex = index + direction
        guard store.preferences.favorites.indices.contains(newIndex) else { return }
        store.update { prefs in
            let item = prefs.favorites.remove(at: index)
            prefs.favorites.insert(item, at: newIndex)
        }
        objectWillChange.send()
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
        panel.message = L10n.s("Elige una carpeta para Favoritos", "Choose a folder for Favorites")
        panel.prompt = L10n.s("Añadir", "Add")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFavorite(url.path)
    }

    func addSelectionToFavorites() {
        let folders = selectedEntries.filter(\.isDirectory)
        guard !folders.isEmpty else {
            statusMessage = L10n.s("Selecciona una carpeta (o usa la carpeta actual)", "Select a folder (or use current folder)")
            return
        }
        for folder in folders {
            addFavorite(folder.path)
        }
        if folders.count > 1 {
            statusMessage = L10n.s("\(folders.count) carpetas en Favoritos", "\(folders.count) folders in Favorites")
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
                self.statusMessage = L10n.s("Suelta carpetas (no archivos sueltos)", "Drop folders (not individual files)")
            } else if added > 1 {
                self.statusMessage = L10n.s("\(added) carpetas en Favoritos", "\(added) folders in Favorites")
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
            ? L10n.s("Orden guardado en todas las carpetas", "Sort order saved across all folders")
            : L10n.s("Orden guardado solo en esta carpeta", "Sort order saved for this folder only")
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
        statusMessage = L10n.s("Esta carpeta usa el default global", "This folder uses global default")
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
        statusMessage = L10n.s("Plantilla «\(template.name)» aplicada", "Preset «\(template.displayName)» applied")
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
            statusMessage = L10n.s("Máximo \(ViewTemplate.maxCount) plantillas", "Maximum \(ViewTemplate.maxCount) presets")
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
        statusMessage = L10n.s("Plantilla «\(name)» guardada", "Preset «\(name)» saved")
    }

    func deleteViewTemplate(_ template: ViewTemplate) {
        viewTemplates.removeAll { $0.id == template.id }
        if activeViewTemplateID == template.id {
            activeViewTemplateID = nil
        }
        store.update { $0.viewTemplates = viewTemplates }
        statusMessage = L10n.s("Plantilla «\(template.name)» eliminada", "Preset «\(template.displayName)» deleted")
    }

    /// Orden por peso: lo más pesado arriba (no borra nada). Se guarda como default.
    func showHeaviestForCleanup() {
        downloadsTodayMode = false
        activeAssistantShortcut = nil
        applyRule(.heaviestFirst, scope: .everywhere)
        let msg = L10n.s(
            "Listo: ordené por peso y lo dejé guardado. Arriba está lo que más ocupa. No borré nada.",
            "Done: sorted by size and saved. Largest files at top. Nothing was deleted."
        )
        appendAgentReply(msg)
    }

    func exitCleanupMode() {
        // Vuelve al estilo Descargas y lo guarda (si no, al reiniciar seguiría en pesados).
        applyRule(.downloads, scope: .everywhere)
        appendAgentReply(L10n.s("Volviste al orden normal (estilo Descargas) y lo guardé.", "Reset to standard sort (Downloads style) and saved."))
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
            ? L10n.s("Modo Descargados: no hay nada de hoy aquí", "Downloads mode: nothing from today here")
            : L10n.s("Modo Descargados: \(n) de hoy (el resto oculto)", "Downloads mode: \(n) from today (others hidden)")
        objectWillChange.send()
    }

    func exitDownloadsTodayMode() {
        downloadsTodayMode = false
        statusMessage = L10n.s("Saliste del modo Descargados", "Exited Downloads mode")
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
            msg = L10n.s("Atajo «\(shortcut.displayTitle)»: no hay nada que coincida en esta carpeta.", "Preset «\(shortcut.displayTitle)»: no matching items in this folder.")
        } else if n == 1 {
            msg = L10n.s("Atajo «\(shortcut.displayTitle)»: 1 archivo. Lo más nuevo arriba.", "Preset «\(shortcut.displayTitle)»: 1 file. Newest on top.")
        } else {
            msg = L10n.s("Atajo «\(shortcut.displayTitle)»: \(n) archivos. Lo más nuevo arriba.", "Preset «\(shortcut.displayTitle)»: \(n) files. Newest on top.")
        }
        appendAgentReply(msg)
        objectWillChange.send()
    }

    func clearAssistantShortcutFilter() {
        guard activeAssistantShortcut != nil else { return }
        activeAssistantShortcut = nil
        appendAgentReply(L10n.s("Quité el filtro del atajo. Otra vez ves toda la carpeta.", "Filter cleared. All folder items visible."))
        objectWillChange.send()
    }

    @discardableResult
    func addAssistantShortcut(_ shortcut: AssistantShortcut) -> String? {
        if assistantShortcuts.count >= AssistantShortcut.maxCount {
            return L10n.s(
                "Ya tienes \(AssistantShortcut.maxCount) atajos (tope). Borra alguno para crear otro.",
                "Limit reached: \(AssistantShortcut.maxCount) presets. Delete one to create another."
            )
        }
        var next = shortcut
        if next.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.title = defaultTitle(for: next)
        }
        assistantShortcuts.insert(next, at: 0)
        persistAssistantShortcuts()
        appendAgentReply(L10n.s("Guardé el atajo «\(next.displayTitle)». Queda fijo aquí para reusarlo.", "Saved preset «\(next.displayTitle)». Available to reuse."))
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
        appendAgentReply(L10n.s("Restauré los atajos de fábrica (\(assistantShortcuts.count)).", "Restored default presets (\(assistantShortcuts.count))."))
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
        statusMessage = L10n.s("Atajo ⌃⌥O abre «\(name)»", "Hotkey ⌃⌥O opens «\(name)»")
    }

    func pickGlobalHotkeyFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L10n.s("Carpeta que abrirá Findaro con ⌃⌥O", "Folder Findaro will open with ⌃⌥O")
        panel.prompt = L10n.s("Usar esta carpeta", "Use This Folder")
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

    var appLanguage: AppLanguage {
        store.preferences.appLanguage
    }

    func setAppLanguage(_ lang: AppLanguage) {
        store.update { $0.appLanguage = lang }
        L10n.activeLanguage = lang
        UserDefaults.standard.set(lang.rawValue, forKey: "findaro_app_language")
        objectWillChange.send()
    }

    private func defaultTitle(for shortcut: AssistantShortcut) -> String {
        let typePart: String
        if shortcut.categories == AssistantShortcut.documentCategories {
            typePart = L10n.s("Documentos", "Documents")
        } else if shortcut.categories.count == 1, let only = shortcut.categories.first {
            typePart = L10n.isEnglish ? only.labelEnglish + "s" : only.labelSpanish + "s"
        } else if shortcut.categories.isEmpty {
            typePart = L10n.s("Archivos", "Files")
        } else {
            typePart = L10n.s("Varios", "Mixed")
        }
        return "\(typePart) \(shortcut.dateWindow.labelLocalized)"
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
        } else if isDiskImage(entry.path) {
            openDiskImage(entry, inSecondary: false)
        } else if ArchiveOps.isExtractable(entry.path) {
            extractArchive(entry, intoSecondary: false)
        } else {
            openFileWithSystem(entry)
        }
    }

    private func isDiskImage(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".dmg")
            || lower.hasSuffix(".iso")
            || lower.hasSuffix(".img")
            || lower.hasSuffix(".sparseimage")
            || lower.hasSuffix(".sparsebundle")
    }

    private func openDiskImage(_ entry: FileEntry, inSecondary: Bool) {
        statusMessage = L10n.s("Montando «\(entry.name)»…", "Mounting «\(entry.name)»…")
        let path = entry.path
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", path, "-plist", "-nobrowse"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let entities = plist["system-entities"] as? [[String: Any]] {
                    let mountPoint = entities.compactMap { $0["mount-point"] as? String }.first
                    if let mountPoint, FileManager.default.fileExists(atPath: mountPoint) {
                        await MainActor.run {
                            if inSecondary {
                                self.navigateSecondary(to: mountPoint)
                            } else {
                                self.navigate(to: mountPoint)
                            }
                            self.statusMessage = L10n.s("Montado: \(URL(fileURLWithPath: mountPoint).lastPathComponent)", "Mounted: \(URL(fileURLWithPath: mountPoint).lastPathComponent)")
                        }
                        return
                    }
                }
            } catch {}

            await MainActor.run {
                self.openFileWithSystem(entry)
            }
        }
    }

    private func openFileWithSystem(_ entry: FileEntry) {
        let url = URL(fileURLWithPath: entry.path)
        if NSWorkspace.shared.open(url) {
            statusMessage = L10n.s("Abrí: \(entry.name)", "Opened: \(entry.name)")
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = [entry.path]
        do {
            try proc.run()
            statusMessage = L10n.s("Abrí: \(entry.name)", "Opened: \(entry.name)")
        } catch {
            statusMessage = L10n.s("No se pudo abrir «\(entry.name)»: \(error.localizedDescription)", "Could not open «\(entry.name)»: \(error.localizedDescription)")
        }
    }

    /// Descomprime zip/tar en esta carpeta y abre el resultado en Findaro (sin Finder).
    func extractArchive(_ entry: FileEntry, intoSecondary: Bool? = nil) {
        let path = entry.path
        guard ArchiveOps.isExtractable(path) else {
            statusMessage = L10n.s("No puedo descomprimir «\(entry.name)» aquí — usa Abrir con", "Cannot extract «\(entry.name)» here — use Open With")
            return
        }
        let secondary = intoSecondary ?? activeIsSecondary
        statusMessage = L10n.s("Descomprimiendo \(entry.name)…", "Extracting \(entry.name)…")
        Task.detached {
            do {
                let result = try ArchiveOps.extract(archivePath: path)
                await MainActor.run {
                    self.finishExtract(resultPath: result, intoSecondary: secondary, archiveName: entry.name)
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = L10n.s("No se pudo descomprimir: \(error.localizedDescription)", "Could not extract: \(error.localizedDescription)")
                }
            }
        }
    }

    private func finishExtract(resultPath: String, intoSecondary: Bool, archiveName: String) {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resultPath, isDirectory: &isDir)
        guard exists else {
            statusMessage = L10n.s("Descomprimí \(archiveName), pero no encuentro el resultado", "Extracted \(archiveName), but cannot find result")
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
        statusMessage = L10n.s("Descomprimido: \(name)", "Extracted: \(name)")
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
                    self.statusMessage = L10n.s("No se pudo abrir: \(error.localizedDescription)", "Could not open: \(error.localizedDescription)")
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
                    self.statusMessage = L10n.s("No se pudo cambiar la app: \(error.localizedDescription)", "Could not change default app: \(error.localizedDescription)")
                } else {
                    let name = FileManager.default.displayName(atPath: appURL.path)
                    self.statusMessage = L10n.s("Ahora \(entry.name) y similares se abren con \(name)", "\(entry.name) and similar files will now open with \(name)")
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
            statusMessage = L10n.s("Selecciona algo para comprimir", "Select items to compress")
            return
        }
        let folder = activeWorkingPath
        let intoSecondary = activeIsSecondary
        let destName: String = {
            if paths.count == 1 {
                let base = URL(fileURLWithPath: paths[0]).deletingPathExtension().lastPathComponent
                return "\(base).zip"
            }
            return L10n.s("Archivo.zip", "Archive.zip")
        }()
        var dest = (folder as NSString).appendingPathComponent(destName)
        var n = 2
        while FileManager.default.fileExists(atPath: dest) {
            let stem = URL(fileURLWithPath: destName).deletingPathExtension().lastPathComponent
            dest = (folder as NSString).appendingPathComponent("\(stem) \(n).zip")
            n += 1
        }
        statusMessage = L10n.s("Comprimiendo…", "Compressing…")
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
                        self.statusMessage = L10n.s("Comprimido: \(URL(fileURLWithPath: dest).lastPathComponent)", "Compressed: \(URL(fileURLWithPath: dest).lastPathComponent)")
                        if intoSecondary {
                            self.reloadSecondary()
                        } else {
                            self.reload()
                        }
                    } else {
                        self.statusMessage = L10n.s("No se pudo comprimir", "Could not compress")
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = L10n.s("No se pudo comprimir: \(error.localizedDescription)", "Could not compress: \(error.localizedDescription)")
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
        if DefaultFileViewerManager.isEnabled {
            let fileURL = URL(fileURLWithPath: entry.path)
            let folderURL = fileURL.hasDirectoryPath ? fileURL : fileURL.deletingLastPathComponent()
            let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            NSWorkspace.shared.open([folderURL], withApplicationAt: finderURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
        }
    }

    func copyPath(_ entry: FileEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.path, forType: .string)
        statusMessage = L10n.s("Ruta copiada: \(entry.path)", "Path copied: \(entry.path)")
    }

    func copySelectedPaths() {
        let paths = selectedEntries.map(\.path)
        guard !paths.isEmpty else {
            // Si no hay selección, copia la carpeta actual.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(currentPath, forType: .string)
            statusMessage = L10n.s("Ruta de carpeta copiada", "Folder path copied")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        statusMessage = paths.count == 1 ? L10n.s("Ruta copiada", "Path copied") : L10n.s("\(paths.count) rutas copiadas", "\(paths.count) paths copied")
    }

    func copyCurrentFolderPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentPath, forType: .string)
        statusMessage = L10n.s("Ruta de carpeta copiada", "Folder path copied")
    }

    func quickLookSelection() {
        let paths = activeSelectedEntries.map(\.path)
        guard !paths.isEmpty else { return }
        QuickLookController.shared.toggle(browser: self, focusing: paths)
    }

    func moveSelectionToTrash() {
        guard ensureLicenseAllowsWrite() else { return }
        // Dentro de la Papelera: borrar para siempre (como Finder).
        if activeIsTrash {
            permanentlyDeleteSelection(confirm: true)
            return
        }
        let targets = activeSelectedEntries
        guard !targets.isEmpty else { return }
        statusMessage = L10n.s("Enviando a la Papelera…", "Moving to Trash…")
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
                    let whereLabel = trashedSecondary ? (L10n.isEnglish ? " (Destination)" : " (Destino)") : ""
                    parts.append(moved == 1
                        ? L10n.s("1 elemento a la Papelera\(whereLabel)", "1 item moved to Trash\(whereLabel)")
                        : L10n.s("\(moved) elementos a la Papelera\(whereLabel)", "\(moved) items moved to Trash\(whereLabel)"))
                }
                if !failures.isEmpty {
                    parts.append(L10n.s("Fallaron \(failures.count): ", "Failed \(failures.count): ") + failures.prefix(3).joined(separator: "; "))
                }
                self.statusMessage = parts.isEmpty
                    ? L10n.s("Nada enviado a la Papelera", "Nothing moved to Trash")
                    : parts.joined(separator: " · ")
            }
        }
    }

    /// Saca los archivos seleccionados de la Papelera y los restaura a una carpeta de destino.
    func restoreSelectionFromTrash(targetDirectory: String? = nil) {
        guard ensureLicenseAllowsWrite() else { return }
        let targets = activeSelectedEntries
        guard !targets.isEmpty else {
            statusMessage = L10n.s("Selecciona archivos para sacar de la Papelera", "Select files to restore from Trash")
            return
        }

        let destination: String
        if let target = targetDirectory, !target.isEmpty {
            destination = (target as NSString).standardizingPath
        } else if dualPaneEnabled && !TrashOps.isTrashPath(secondaryPath) {
            destination = (secondaryPath as NSString).standardizingPath
        } else {
            let desktop = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop")
            destination = FileManager.default.fileExists(atPath: desktop)
                ? desktop
                : GlobalHotKey.defaultDownloadsPath()
        }

        let paths = targets.map(\.path)
        clearActiveSelection()
        statusMessage = L10n.s("Sacando de la Papelera…", "Restoring from Trash…")

        Task {
            do {
                let moved = try await Task.detached(priority: .userInitiated) {
                    do {
                        return try FileOps.transfer(paths: paths, toDirectory: destination, move: true)
                    } catch {
                        // Fallback a Finder si macOS bloquea mover archivos directamente desde la Papelera
                        var pairs: [FileOps.TransferPair] = []
                        for p in paths {
                            if let newPath = try? TrashOps.moveViaFinder(source: p, destDir: destination) {
                                pairs.append(FileOps.TransferPair(from: p, to: newPath))
                            }
                        }
                        if !pairs.isEmpty {
                            return pairs
                        }
                        throw error
                    }
                }.value
                await MainActor.run {
                    self.reload()
                    if self.dualPaneEnabled { self.reloadSecondary() }
                    let destName = URL(fileURLWithPath: destination).lastPathComponent
                    self.statusMessage = moved.count == 1
                        ? L10n.s("Restaurado en «\(destName)»: \(URL(fileURLWithPath: moved[0].to).lastPathComponent)", "Restored to «\(destName)»: \(URL(fileURLWithPath: moved[0].to).lastPathComponent)")
                        : L10n.s("\(moved.count) archivos restaurados en «\(destName)»", "\(moved.count) items restored to «\(destName)»")
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = L10n.s("No se pudo restaurar: \(error.localizedDescription)", "Could not restore: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Permite al usuario elegir interactivamente a qué carpeta restaurar los archivos de la Papelera.
    func restoreSelectionFromTrashPromptFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.s("Restaurar aquí", "Restore Here")
        panel.message = L10n.s("Elige la carpeta donde deseas restaurar los archivos de la Papelera", "Choose the folder where you want to restore Trash items")
        if panel.runModal() == .OK, let url = panel.url {
            restoreSelectionFromTrash(targetDirectory: url.path)
        }
    }

    /// Borra de verdad lo seleccionado (solo tiene sentido en la Papelera).
    func permanentlyDeleteSelection(confirm: Bool) {
        guard ensureLicenseAllowsWrite() else { return }
        let targets = activeSelectedEntries
        guard !targets.isEmpty else {
            statusMessage = L10n.s("Selecciona algo en la Papelera", "Select items in Trash")
            return
        }
        if confirm {
            let alert = NSAlert()
            alert.messageText = targets.count == 1
                ? L10n.s("¿Eliminar «\(targets[0].name)» para siempre?", "Delete «\(targets[0].name)» permanently?")
                : L10n.s("¿Eliminar \(targets.count) elementos para siempre?", "Delete \(targets.count) items permanently?")
            alert.informativeText = L10n.s("No se pueden recuperar desde la Papelera.", "They cannot be recovered from Trash.")
            alert.alertStyle = .critical
            alert.addButton(withTitle: L10n.s("Eliminar para siempre", "Delete Permanently"))
            alert.addButton(withTitle: L10n.s("Cancelar", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let paths = targets.map(\.path)
        clearActiveSelection()
        statusMessage = L10n.s("Eliminando…", "Deleting…")
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
            alert.messageText = L10n.s("¿Vaciar la Papelera?", "Empty Trash?")
            alert.informativeText = L10n.s("Se eliminarán para siempre todos los elementos de la Papelera.", "All items in the Trash will be permanently erased.")
            alert.alertStyle = .critical
            alert.addButton(withTitle: L10n.s("Vaciar Papelera", "Empty Trash"))
            alert.addButton(withTitle: L10n.s("Cancelar", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        // Asegura que estamos en la ruta canónica.
        if !isViewingTrash {
            navigate(to: TrashOps.userTrashPath, recordHistory: true)
        }
        statusMessage = L10n.s("Vaciando Papelera…", "Emptying Trash…")
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
                    self.statusMessage = L10n.s("Papelera vaciada (Finder)", "Trash emptied (Finder)")
                } else if result.ok == 0, result.failures.isEmpty {
                    self.statusMessage = L10n.s("La Papelera ya estaba vacía", "Trash was already empty")
                } else {
                    var parts: [String] = []
                    if result.ok > 0 {
                        parts.append(L10n.s("Papelera: \(result.ok) eliminados", "Trash: \(result.ok) permanently deleted"))
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
        guard ensureLicenseAllowsWrite() else { return }
        nameDraft = L10n.s("Carpeta sin título", "Untitled Folder")
        showNewFolderDialog = true
    }

    func createFolderFromDraft() {
        guard ensureLicenseAllowsWrite() else { return }
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
            statusMessage = L10n.s("Carpeta creada: \(URL(fileURLWithPath: path).lastPathComponent)", "Folder created: \(URL(fileURLWithPath: path).lastPathComponent)")
        } catch {
            statusMessage = L10n.s("No se pudo crear: \(error.localizedDescription)", "Could not create: \(error.localizedDescription)")
        }
    }

    func promptNewFile() {
        guard ensureLicenseAllowsWrite() else { return }
        nameDraft = L10n.s("Sin título.txt", "Untitled.txt")
        showNewFileDialog = true
    }

    func createFileFromDraft() {
        guard ensureLicenseAllowsWrite() else { return }
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
            statusMessage = L10n.s("Archivo creado: \(URL(fileURLWithPath: path).lastPathComponent)", "File created: \(URL(fileURLWithPath: path).lastPathComponent)")
        } catch {
            statusMessage = L10n.s("No se pudo crear: \(error.localizedDescription)", "Could not create: \(error.localizedDescription)")
        }
    }

    func promptRename() {
        guard ensureLicenseAllowsWrite() else { return }
        guard let entry = activeSelectedEntries.first else {
            statusMessage = L10n.s("Selecciona un ítem para renombrar", "Select an item to rename")
            return
        }
        renameTargetPath = entry.path
        nameDraft = entry.name
        showRenameDialog = true
    }

    func commitRenameFromDraft() {
        guard ensureLicenseAllowsWrite() else { return }
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
            statusMessage = L10n.s("Renombrado a \(newName)", "Renamed to \(newName)")
        } catch {
            statusMessage = L10n.s("No se pudo renombrar: \(error.localizedDescription)", "Could not rename: \(error.localizedDescription)")
        }
        renameTargetPath = nil
    }

    func duplicateSelection() {
        guard ensureLicenseAllowsWrite() else { return }
        let targets = activeSelectedEntries
        guard !targets.isEmpty else {
            statusMessage = L10n.s("Selecciona algo para duplicar", "Select items to duplicate")
            return
        }
        statusMessage = L10n.s("Duplicando…", "Duplicating…")
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
                        ? L10n.s(
                            "No se pudo duplicar \(name): \(error.localizedDescription)",
                            "Could not duplicate \(name): \(error.localizedDescription)"
                        )
                        : L10n.s(
                            "Duplicación parcial (\(createdPaths.count) elemento(s)); ⌘Z deshace lo creado. \(error.localizedDescription)",
                            "Partial duplication (\(createdPaths.count) item(s)); ⌘Z undos created items. \(error.localizedDescription)"
                        )
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
        if !SharedShelf.shared.items.isEmpty {
            shelf = SharedShelf.shared.items
        }
        if !shelf.isEmpty {
            depositShelfHere()
            return
        }
        // Fallback: portapapeles del sistema (Finder, etc.)
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            statusMessage = L10n.s("Bandeja y portapapeles vacíos", "Tray and clipboard are empty")
            return
        }
        guard pendingMergePreview == nil else {
            statusMessage = L10n.s("Primero termina o cancela la fusión pendiente", "Complete or cancel the pending merge first")
            return
        }
        let paths = urls.map(\.path)
        let dest = activeWorkingPath
        let rest = offerMergeIfNeeded(paths: paths, toDirectory: dest, move: false)
        if pendingMergePreview != nil {
            statusMessage = L10n.s("Revisa Smart Merge; vuelve a pegar para continuar con los demás elementos", "Review Smart Merge; paste again to continue with remaining items")
            return
        }
        guard !rest.isEmpty else { return }
        enqueueTransfer(paths: rest, toDirectory: dest, move: false) { result in
            switch result {
            case .success(let pairs):
                self.pushUndo(.copied(created: pairs.map(\.to)))
                self.reload()
                if self.dualPaneEnabled { self.reloadSecondary() }
                self.statusMessage = pairs.count == 1
                    ? L10n.s("1 archivo pegado", "1 file pasted")
                    : L10n.s("\(pairs.count) archivos pegados", "\(pairs.count) files pasted")
            case .failure(let error):
                self.statusMessage = L10n.s("No se pudo pegar: \(error.localizedDescription)", "Could not paste: \(error.localizedDescription)")
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
        guard ensureLicenseAllowsWrite() else { return }
        let entries = activeSelectedEntries
        guard !entries.isEmpty else {
            statusMessage = L10n.s("Selecciona algo para la bandeja", "Select items for the tray")
            return
        }
        for entry in entries {
            upsertShelfItem(FileOps.ShelfItem(entry: entry, intent: intent))
        }
        // Portapapeles general del sistema (para pegar entre pestañas y con otras apps)
        let pb = NSPasteboard.general
        pb.clearContents()
        let urls = entries.map { URL(fileURLWithPath: $0.path) } as [NSURL]
        pb.writeObjects(urls)

        SharedShelf.shared.items = shelf
        NotificationCenter.default.post(name: SharedShelf.didChangeNotification, object: self)

        let verb = intent == .move ? L10n.s("para mover", "to move") : L10n.s("para copiar", "to copy")
        statusMessage = entries.count == 1
            ? L10n.s("En bandeja \(verb) — ve abajo o ⌘V aquí", "In clipboard tray \(verb) — navigate or ⌘V here")
            : L10n.s("\(entries.count) en bandeja \(verb) — ⌘V suelta aquí", "\(entries.count) in clipboard tray \(verb) — ⌘V pastes here")
        objectWillChange.send()
    }

    func addPathsToShelf(_ paths: [String], intent: FileOps.ShelfIntent = .move) {
        guard ensureLicenseAllowsWrite() else { return }
        for path in paths {
            let name = URL(fileURLWithPath: path).lastPathComponent
            upsertShelfItem(FileOps.ShelfItem(path: path, name: name, intent: intent))
        }
        SharedShelf.shared.items = shelf
        NotificationCenter.default.post(name: SharedShelf.didChangeNotification, object: self)
        statusMessage = L10n.s("Bandeja: \(shelf.count) ítem(s)", "Tray: \(shelf.count) item(s)")
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
        SharedShelf.shared.items = shelf
        NotificationCenter.default.post(name: SharedShelf.didChangeNotification, object: self)
    }

    func clearShelf() {
        shelf.removeAll()
        SharedShelf.shared.items.removeAll()
        NotificationCenter.default.post(name: SharedShelf.didChangeNotification, object: self)
        statusMessage = L10n.s("Bandeja vacía", "Tray empty")
    }

    func moveShelfHere() {
        transferShelf(forceMove: true)
    }

    func copyShelfHere() {
        transferShelf(forceMove: false)
    }

    /// Respeta la intención de cada ítem (⌘C copia / ⌘X mueve).
    func depositShelfHere() {
        guard ensureLicenseAllowsWrite() else { return }
        guard !shelf.isEmpty else {
            statusMessage = L10n.s("La bandeja está vacía", "The tray is empty")
            return
        }
        guard pendingMergePreview == nil else {
            statusMessage = L10n.s("Primero termina o cancela la fusión pendiente", "Complete or cancel the pending merge first")
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
            statusMessage = L10n.s("Revisa Smart Merge; los demás elementos siguen en la bandeja", "Review Smart Merge; remaining items stay in tray")
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
            SharedShelf.shared.items = shelf
            NotificationCenter.default.post(name: SharedShelf.didChangeNotification, object: self)
            if !moved.isEmpty { pushUndo(.moved(pairs: moved)) }
            if !copied.isEmpty { pushUndo(.copied(created: copied.map(\.to))) }
            reload()
            if dualPaneEnabled { reloadSecondary() }
            var parts: [String] = []
            if !moved.isEmpty { parts.append(L10n.s("\(moved.count) movido(s)", "\(moved.count) moved")) }
            if !copied.isEmpty { parts.append(L10n.s("\(copied.count) copiado(s)", "\(copied.count) copied")) }
            if let error {
                statusMessage = parts.isEmpty
                    ? L10n.s("No se completó la transferencia: \(error)", "Transfer could not be completed: \(error)")
                    : L10n.s("Transferencia parcial: \(parts.joined(separator: " · ")). \(error)", "Partial transfer: \(parts.joined(separator: " · ")). \(error)")
            } else {
                statusMessage = parts.isEmpty
                    ? L10n.s("Nada transferido", "Nothing transferred")
                    : parts.joined(separator: " · ") + L10n.s(" · ⌘Z deshace", " · ⌘Z undoes")
            }
        }

        if toMove.isEmpty && toCopy.isEmpty {
            shelf = remaining
            SharedShelf.shared.items = shelf
            NotificationCenter.default.post(name: SharedShelf.didChangeNotification, object: self)
            reload()
            if dualPaneEnabled { reloadSecondary() }
            statusMessage = L10n.s("Nada transferido", "Nothing transferred")
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
            statusMessage = L10n.s("La bandeja está vacía", "The tray is empty")
            return
        }
        guard pendingMergePreview == nil else {
            statusMessage = L10n.s("Primero termina o cancela la fusión pendiente", "Complete or cancel the pending merge first")
            return
        }
        let dest = activeWorkingPath
        let rest = offerMergeIfNeeded(paths: paths, toDirectory: dest, move: forceMove)
        if pendingMergePreview != nil {
            statusMessage = L10n.s("Revisa Smart Merge; los demás elementos siguen en la bandeja", "Review Smart Merge; remaining items stay in tray")
            return
        }
        guard !rest.isEmpty else { return }
        let job = TransferQueue.Job(paths: rest, destinationDir: dest, move: forceMove)
        transferProgressFraction = 0
        transferProgressLabel = forceMove
            ? L10n.s("Moviendo bandeja…", "Moving tray items…")
            : L10n.s("Copiando bandeja…", "Copying tray items…")
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
                SharedShelf.shared.items = self.shelf
                NotificationCenter.default.post(name: SharedShelf.didChangeNotification, object: self)
                self.reload()
                if self.dualPaneEnabled { self.reloadSecondary() }
                self.statusMessage = forceMove
                    ? L10n.s("Movidos \(pairs.count) a esta carpeta · ⌘Z deshace", "Moved \(pairs.count) items to this folder · ⌘Z undoes")
                    : L10n.s("Copiados \(pairs.count) a esta carpeta · ⌘Z deshace", "Copied \(pairs.count) items to this folder · ⌘Z undoes")
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
            statusMessage = L10n.s("Nada que deshacer", "Nothing to undo")
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
                    ? L10n.s("No se pudo deshacer el movimiento", "Could not undo file move")
                    : L10n.s("Deshecho: \(restored) movido(s) de vuelta", "Undone: \(restored) item(s) moved back")

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
                    ? L10n.s("No se pudo deshacer la copia", "Could not undo copy")
                    : L10n.s("Deshecho: \(trashed) copia(s) a la Papelera", "Undone: \(trashed) copy/copies moved to Trash")

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
                statusMessage = L10n.s(
                    "Smart Merge deshecho: \(removedCopies) copia(s) retiradas, \(restoredBackups) respaldo(s) restaurado(s)",
                    "Smart Merge undone: \(removedCopies) copy/copies removed, \(restoredBackups) backup(s) restored"
                )
                if sourceOriginalPath != nil && !restoredSource {
                    statusMessage = (statusMessage ?? "") + L10n.s(" · No encontré el origen en la Papelera", " · Original folder not found in Trash")
                }
            }
            undoStack.removeLast()
        } catch {
            // Conserva el registro para permitir reintentar lo que no se pudo revertir.
            statusMessage = L10n.s(
                "Deshacer quedó incompleto; puedes reintentar: \(error.localizedDescription)",
                "Undo was incomplete; you can retry: \(error.localizedDescription)"
            )
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
            statusMessage = L10n.s("Selecciona archivos o llena la bandeja", "Select files or add items to clipboard tray")
            return
        }
        let dropoverURL: URL? =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "me.damir.dropover-mac")
            ?? {
                let fallback = URL(fileURLWithPath: "/Applications/Dropover.app", isDirectory: true)
                return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
            }()
        guard let dropoverURL else {
            statusMessage = L10n.s("No encontré Dropover.app en /Applications", "Dropover.app not found in /Applications")
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
                        ? L10n.s("En Dropover — arrástralo a Terminal o Cursor", "In Dropover — drag to Terminal or other apps")
                        : L10n.s("\(paths.count) en Dropover — arrástralos a otra app", "\(paths.count) in Dropover — drag to other apps")
                }
            }
        }
    }

    /// Copia rutas POSIX entrecomilladas (útil en Terminal / pegar en Cursor).
    func copyOutboundPaths() {
        let paths = outboundPaths
        guard !paths.isEmpty else {
            statusMessage = L10n.s("Nada seleccionado para copiar rutas", "No items selected to copy paths")
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
            statusMessage = L10n.s("Ese destino no es una carpeta", "Destination is not a folder")
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
            statusMessage = L10n.s("No se puede soltar ahí", "Cannot drop items here")
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

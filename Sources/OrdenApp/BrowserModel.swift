import Foundation
import SwiftUI
import OrdenCore
import AppKit

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

    let store: PreferencesStore
    private var measureTask: Task<Void, Never>?

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let start = store.preferences.lastPath
            ?? (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent("Downloads")
        self.currentPath = start
        self.rule = store.preferences.rule(for: start)
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
        searchText = ""
        statusMessage = nil
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
        reload()
        if moved > 0 {
            statusMessage = moved == 1 ? "1 elemento a la Papelera" : "\(moved) elementos a la Papelera"
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

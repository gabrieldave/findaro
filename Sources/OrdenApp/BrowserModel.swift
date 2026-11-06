import Foundation
import SwiftUI
import OrdenCore
import Combine

@MainActor
final class BrowserModel: ObservableObject {
    @Published var currentPath: String
    @Published var entries: [FileEntry] = []
    @Published var selectedIDs: Set<String> = []
    @Published var rule: SortRule
    @Published var errorMessage: String?
    @Published var searchText: String = ""

    let store: PreferencesStore

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
        return base.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var ruleSummary: String { rule.summarySpanish }

    func reload() {
        do {
            entries = try DirectoryLoader.load(path: currentPath)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    func navigate(to path: String) {
        currentPath = path
        rule = store.preferences.rule(for: path)
        selectedIDs = []
        searchText = ""
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

    func applyRule(_ newRule: SortRule, saveAsFolderDefault: Bool) {
        rule = newRule
        store.update { prefs in
            prefs.globalRule = newRule
            if saveAsFolderDefault {
                prefs.folderOverrides[currentPath] = newRule
            }
        }
        // Re-sort only; no reload needed
        objectWillChange.send()
    }

    func open(_ entry: FileEntry) {
        if entry.isDirectory {
            navigate(to: entry.path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path))
        }
    }

    func revealInFinder(_ entry: FileEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }

    func copyPath(_ entry: FileEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.path, forType: .string)
    }

    private func home(_ component: String) -> String {
        (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
            .appendingPathComponent(component)
    }
}

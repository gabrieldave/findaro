import AppKit
@preconcurrency import QuickLookUI
import OrdenCore

/// Panel de Quick Look estilo Finder (Space).
/// ← = más nuevo · → = más viejo · al final vuelve a empezar (circular).
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private weak var browser: BrowserModel?
    /// Archivos navegables ordenados: más nuevo → más viejo.
    private var entries: [FileEntry] = []
    private var currentIndex: Int = 0

    private var urls: [URL] {
        entries.map { URL(fileURLWithPath: $0.path) }
    }

    var isVisible: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }

    func toggle(browser: BrowserModel, focusing paths: [String]) {
        self.browser = browser
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        show(browser: browser, focusing: paths)
    }

    func show(browser: BrowserModel, focusing paths: [String]) {
        self.browser = browser
        rebuildEntries(focusing: paths)
        guard !entries.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        syncBrowserSelection()
    }

    /// ← más nuevo (−1) · → más viejo (+1). Circular.
    func navigate(delta: Int) {
        guard !entries.isEmpty else { return }
        let n = entries.count
        currentIndex = (currentIndex + delta % n + n) % n
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
        syncBrowserSelection()
    }

    private func rebuildEntries(focusing paths: [String]) {
        guard let browser else {
            entries = []
            currentIndex = 0
            return
        }
        // Mismo conjunto que la carpeta visible; orden por Agregado (nuevo → viejo).
        let files = browser.visibleEntries.filter { !$0.isDirectory }
        entries = files.sorted { lhs, rhs in
            if lhs.dateAdded != rhs.dateAdded {
                return lhs.dateAdded > rhs.dateAdded
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        let focus = paths.first ?? browser.selectedEntries.first(where: { !$0.isDirectory })?.path
        if let focus, let idx = entries.firstIndex(where: { $0.path == focus }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
    }

    private func syncBrowserSelection() {
        guard let browser, entries.indices.contains(currentIndex) else { return }
        let entry = entries[currentIndex]
        browser.selectOnly(entry.id)
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { entries.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard entries.indices.contains(index) else { return nil }
            return URL(fileURLWithPath: entries[index].path) as NSURL
        }
    }

    // MARK: - QLPreviewPanelDelegate

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = !flags.contains(.option)
            && !flags.contains(.command)
            && !flags.contains(.control)
            && !flags.contains(.shift)
        guard plain else { return false }

        return MainActor.assumeIsolated {
            switch keyCode {
            case 123: // ← más nuevo
                navigate(delta: -1)
                return true
            case 124: // → más viejo
                navigate(delta: 1)
                return true
            default:
                return false
            }
        }
    }
}

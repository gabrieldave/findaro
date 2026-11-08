import AppKit
@preconcurrency import QuickLookUI
import OrdenCore

/// Vista previa (Space): vídeo/imagen con motor propio; el resto con Quick Look.
/// ← = más nuevo · → = más viejo · circular.
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private weak var browser: BrowserModel?
    private var entries: [FileEntry] = []
    private var currentIndex: Int = 0

    var isVisible: Bool {
        MediaPreviewController.shared.isVisible
            || QLPreviewPanel.shared()?.isVisible == true
    }

    func toggle(browser: BrowserModel, focusing paths: [String]) {
        self.browser = browser
        if isVisible {
            hideAll()
            return
        }
        show(browser: browser, focusing: paths)
    }

    func show(browser: BrowserModel, focusing paths: [String]) {
        self.browser = browser
        rebuildEntries(focusing: paths)
        guard !entries.isEmpty else { return }
        presentCurrent()
        syncBrowserSelection()
    }

    /// ← más nuevo (−1) · → más viejo (+1). Circular.
    func navigate(delta: Int) {
        guard !entries.isEmpty else { return }
        let n = entries.count
        currentIndex = (currentIndex + delta % n + n) % n
        presentCurrent()
        syncBrowserSelection()
    }

    private func hideAll() {
        MediaPreviewController.shared.hide()
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    private func presentCurrent() {
        guard entries.indices.contains(currentIndex) else { return }
        let entry = entries[currentIndex]
        switch entry.category {
        case .video:
            QLPreviewPanel.shared()?.orderOut(nil)
            MediaPreviewController.shared.show(entry: entry)
        default:
            MediaPreviewController.shared.hide()
            guard let panel = QLPreviewPanel.shared() else {
                MediaPreviewController.shared.show(entry: entry)
                return
            }
            panel.dataSource = self
            panel.delegate = self
            panel.currentPreviewItemIndex = currentIndex
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func rebuildEntries(focusing paths: [String]) {
        guard let browser else {
            entries = []
            currentIndex = 0
            return
        }
        let sourceEntries = browser.activeIsSecondary ? browser.secondaryEntries : browser.visibleEntries
        let files = sourceEntries.filter { !$0.isDirectory }
        // Respetar el orden exacto de la vista actual (filtros, atajos o regla activa)
        entries = files
        let focus = paths.first ?? (browser.activeIsSecondary ? browser.secondarySelectedEntries : browser.selectedEntries).first(where: { !$0.isDirectory })?.path
        if let focus, let idx = entries.firstIndex(where: { $0.path == focus }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
    }

    private func syncBrowserSelection() {
        guard let browser, entries.indices.contains(currentIndex) else { return }
        browser.selectOnly(entries[currentIndex].id)
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
            case 123:
                navigate(delta: -1)
                return true
            case 124:
                navigate(delta: 1)
                return true
            case 49: // space cierra
                hideAll()
                return true
            case 53: // esc
                hideAll()
                return true
            default:
                return false
            }
        }
    }
}

extension NSApplication {
    nonisolated open override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    nonisolated open override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.delegate = QuickLookController.shared
            panel.dataSource = QuickLookController.shared
        }
    }

    nonisolated open override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    }
}

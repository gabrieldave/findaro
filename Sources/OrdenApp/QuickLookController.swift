import AppKit
import OrdenCore

/// Coordinador de Vista rápida: lista circular de archivos + MediaPreviewController.
/// SIN `QLPreviewPanel.shared()` (deja estado fantasma multi-monitor).
@MainActor
final class QuickLookController {
    static let shared = QuickLookController()

    private weak var browser: BrowserModel?
    private var entries: [FileEntry] = []
    private var currentIndex: Int = 0
    private var lastToggleAt: Date?
    private var lastToggleFocusPath: String?

    var isVisible: Bool {
        MediaPreviewController.shared.isActuallyVisibleOnScreen
    }

    var currentPreviewPath: String? {
        MediaPreviewController.shared.currentURL?.path
            ?? (entries.indices.contains(currentIndex) ? entries[currentIndex].path : nil)
    }

    func resetAfterDisplayChange() {
        lastToggleAt = nil
        lastToggleFocusPath = nil
        MediaPreviewController.shared.dismiss(restoreFocus: false)
        if let browser {
            browser.mediaPreviewEntry = nil
        }
    }

    func hide() {
        MediaPreviewController.shared.dismiss(restoreFocus: true)
        browser?.mediaPreviewEntry = nil
    }

    /// Botón / ojito: siempre abre.
    func presentExplicit(browser: BrowserModel, focusing paths: [String]) {
        self.browser = browser
        rebuildEntries(focusing: paths)
        guard !entries.isEmpty else {
            browser.statusMessage = L10n.s(
                "No hay archivo para Vista rápida",
                "No file to Quick Look"
            )
            return
        }
        presentCurrent()
        syncBrowserSelection()
    }

    /// Solo Espacio: cierra si ya muestra ESE archivo en pantalla; si no, presenta.
    func toggleFromSpace(browser: BrowserModel, focusing paths: [String]) {
        self.browser = browser

        let focus = paths.first
        let now = Date()
        if let last = lastToggleAt,
           now.timeIntervalSince(last) < 0.18,
           lastToggleFocusPath == focus {
            return
        }
        lastToggleAt = now
        lastToggleFocusPath = focus

        if let focus,
           MediaPreviewController.shared.isActuallyVisibleOnScreen,
           MediaPreviewController.shared.currentURL?.standardizedFileURL
            == URL(fileURLWithPath: focus).standardizedFileURL {
            MediaPreviewController.shared.dismiss(restoreFocus: true)
            browser.mediaPreviewEntry = nil
            return
        }

        presentExplicit(browser: browser, focusing: paths)
    }

    /// Compat menú / callers antiguos → present forzado.
    func toggle(browser: BrowserModel, focusing paths: [String]) {
        presentExplicit(browser: browser, focusing: paths)
    }

    func show(browser: BrowserModel, focusing paths: [String]) {
        presentExplicit(browser: browser, focusing: paths)
    }

    /// ← más nuevo (−1) · → más viejo (+1). Circular.
    func navigate(delta: Int) {
        guard !entries.isEmpty else { return }
        let n = entries.count
        currentIndex = (currentIndex + delta % n + n) % n
        presentCurrent()
        syncBrowserSelection()
    }

    private func presentCurrent() {
        guard entries.indices.contains(currentIndex) else { return }
        let entry = entries[currentIndex]
        browser?.mediaPreviewEntry = entry
        MediaPreviewController.shared.present(
            url: URL(fileURLWithPath: entry.path),
            hostWindow: browser?.hostWindow
        )
    }

    private func rebuildEntries(focusing paths: [String]) {
        guard let browser else {
            entries = []
            currentIndex = 0
            return
        }
        let sourceEntries = browser.activeIsSecondary ? browser.secondaryEntries : browser.visibleEntries
        let files = sourceEntries.filter { !$0.isDirectory }
        entries = files
        let focus = paths.first(where: { path in
            files.contains(where: { $0.path == path })
        }) ?? (browser.activeIsSecondary ? browser.secondarySelectedEntries : browser.selectedEntries)
            .first(where: { !$0.isDirectory })?.path
        if let focus, let idx = entries.firstIndex(where: { $0.path == focus }) {
            currentIndex = idx
        } else if let firstPath = paths.first,
                  let idx = entries.firstIndex(where: { $0.path == firstPath }) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }
    }

    private func syncBrowserSelection() {
        guard let browser, entries.indices.contains(currentIndex) else { return }
        browser.selectOnly(entries[currentIndex].id)
    }
}

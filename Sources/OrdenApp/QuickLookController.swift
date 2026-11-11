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
    /// Evita open→close si Espacio llega por monitor + SwiftUI en el mismo instante.
    private var lastToggleAt: Date?

    var isVisible: Bool {
        if MediaPreviewController.shared.isVisible { return true }
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return false }
        // Panel “visible” pero off-screen no cuenta: Espacio debe ABRIR overlay, no “cerrar”.
        return Self.isQuickLookOnScreen(panel)
    }

    func toggle(browser: BrowserModel, focusing paths: [String]) {
        self.browser = browser
        let now = Date()
        if let last = lastToggleAt, now.timeIntervalSince(last) < 0.18 {
            return
        }
        lastToggleAt = now
        if MediaPreviewController.shared.isVisible {
            MediaPreviewController.shared.hide()
            return
        }
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            // Off-screen: no lo trates como abierto; ordénalo out y muestra de verdad.
            if Self.isQuickLookOnScreen(panel) {
                panel.orderOut(nil)
                return
            }
            panel.orderOut(nil)
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

    func hide() {
        hideAll()
    }

    private func hideAll() {
        MediaPreviewController.shared.hide()
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    private func presentCurrent() {
        guard entries.indices.contains(currentIndex) else { return }
        let entry = entries[currentIndex]
        // Imagen + vídeo: SIEMPRE overlay dentro de Findaro.
        // QLPreviewPanel en multi-monitor (LG+TYPEC) a menudo queda off-screen:
        // el usuario pulsa Espacio y “no pasa nada” aunque el panel exista.
        if entry.category == .video || entry.category == .image {
            presentInline(entry)
            return
        }

        MediaPreviewController.shared.hide()
        guard let panel = QLPreviewPanel.shared() else {
            presentInline(entry)
            return
        }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = currentIndex
        panel.reloadData()
        panel.updateController()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if !panel.isVisible {
            panel.updateController()
            panel.makeKeyAndOrderFront(nil)
        }
        // Si el panel nació fuera de pantalla, caemos al overlay (PDF/otros).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !Self.isQuickLookOnScreen(panel) {
                panel.orderOut(nil)
                self.presentInline(entry)
            }
        }
    }

    private func presentInline(_ entry: FileEntry) {
        if let browser {
            MediaPreviewController.shared.bind(browser: browser)
        }
        QLPreviewPanel.shared()?.orderOut(nil)
        MediaPreviewController.shared.show(entry: entry)
    }

    private static func isQuickLookOnScreen(_ panel: QLPreviewPanel) -> Bool {
        FindaroScreenPlacement.isWindowOnScreen(panel)
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

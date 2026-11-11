import AppKit
import AVKit
import QuickLookUI
import UniformTypeIdentifiers
import OrdenCore

private final class EphemeralPreviewPanel: NSPanel {
    var onCloseKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCloseKey?()
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        // 53 = Esc, 49 = Space
        if event.keyCode == 53 || event.keyCode == 49 {
            onCloseKey?()
            return
        }
        // ← → navegan la lista del explorador
        if event.keyCode == 123 {
            QuickLookController.shared.navigate(delta: -1)
            return
        }
        if event.keyCode == 124 {
            QuickLookController.shared.navigate(delta: 1)
            return
        }
        super.keyDown(with: event)
    }
}

/// Preview multi-monitor: NSPanel efímero (se destruye en cada dismiss).
/// Imagen → NSImageView · Vídeo/Audio → AVPlayerView · resto → QLPreviewView.
/// Nunca `QLPreviewPanel.shared()` ni `addChildWindow`.
@MainActor
final class MediaPreviewController: NSObject, NSWindowDelegate {
    static let shared = MediaPreviewController()

    private var panel: EphemeralPreviewPanel?
    private weak var avPlayer: AVPlayer?
    private weak var qlPreviewView: QLPreviewView?
    private weak var currentHostWindow: NSWindow?
    private(set) var currentURL: URL?

    var isActuallyVisibleOnScreen: Bool {
        guard let panel, panel.isVisible, panel.alphaValue > 0.01 else { return false }
        return NSScreen.screens.contains { !$0.frame.intersection(panel.frame).isNull }
    }

    /// Compat: mismos callers antiguos.
    var isVisible: Bool { isActuallyVisibleOnScreen }

    func isPreviewWindow(_ window: NSWindow?) -> Bool {
        guard let window, let panel else { return false }
        return window === panel
    }

    /// Botón «Vista rápida» / ojito: SIEMPRE abre/actualiza, nunca toggle.
    func present(url: URL, hostWindow: NSWindow?) {
        let resolvedHost = hostWindow
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })

        dismiss(restoreFocus: false)

        guard let resolvedHost else { return }
        currentHostWindow = resolvedHost
        currentURL = url

        let (contentView, naturalSize) = makeContentView(for: url)
        let targetFrame = computePanelFrame(naturalSize: naturalSize, hostWindow: resolvedHost)

        let newPanel = EphemeralPreviewPanel(
            contentRect: targetFrame,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        newPanel.isReleasedWhenClosed = false
        newPanel.title = url.lastPathComponent
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = true
        newPanel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        newPanel.delegate = self
        newPanel.onCloseKey = { [weak self] in
            self?.dismiss(restoreFocus: true)
        }

        contentView.frame = NSRect(origin: .zero, size: targetFrame.size)
        contentView.autoresizingMask = [.width, .height]
        newPanel.contentView = contentView

        self.panel = newPanel
        newPanel.setFrame(targetFrame, display: true)
        newPanel.makeKeyAndOrderFront(nil)
    }

    /// Solo para la tecla Espacio.
    func toggle(url: URL, hostWindow: NSWindow?) {
        if isActuallyVisibleOnScreen, currentURL?.standardizedFileURL == url.standardizedFileURL {
            dismiss(restoreFocus: true)
        } else {
            present(url: url, hostWindow: hostWindow)
        }
    }

    /// Cierre total: destruye el NSPanel (sin estado fantasma entre monitores/carpetas).
    func dismiss(restoreFocus: Bool = false) {
        let hostToRestore = currentHostWindow

        avPlayer?.pause()
        avPlayer = nil

        if let qlView = qlPreviewView {
            qlView.previewItem = nil
            qlView.close()
            qlPreviewView = nil
        }

        if let existingPanel = panel {
            existingPanel.delegate = nil
            existingPanel.onCloseKey = nil
            if let parent = existingPanel.parent {
                parent.removeChildWindow(existingPanel)
            }
            existingPanel.orderOut(nil)
            existingPanel.close()
        }

        panel = nil
        currentURL = nil
        currentHostWindow = nil

        if restoreFocus, let host = hostToRestore, host.isVisible, NSApp.isActive {
            host.makeKey()
        }
    }

    func resetAfterDisplayChange() {
        dismiss(restoreFocus: false)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss(restoreFocus: true)
        return false
    }

    // MARK: - Content

    private func makeContentView(for url: URL) -> (NSView, CGSize?) {
        let type = UTType(filenameExtension: url.pathExtension)

        if let type, type.conforms(to: .image), let image = NSImage(contentsOf: url) {
            let imageView = NSImageView()
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.animates = true
            return (imageView, image.size)
        }

        if let type, type.conforms(to: .audiovisualContent) || type.conforms(to: .movie) || type.conforms(to: .audio) {
            let player = AVPlayer(url: url)
            let playerView = AVPlayerView()
            playerView.player = player
            playerView.controlsStyle = .floating
            self.avPlayer = player
            player.play()
            return (playerView, CGSize(width: 960, height: 540))
        }

        if let qlView = QLPreviewView(frame: .zero, style: .normal) {
            qlView.autostarts = true
            qlView.previewItem = url as NSURL
            self.qlPreviewView = qlView
            return (qlView, CGSize(width: 820, height: 640))
        }

        let fallback = NSTextField(labelWithString: url.lastPathComponent)
        fallback.alignment = .center
        return (fallback, CGSize(width: 420, height: 260))
    }

    // MARK: - Placement (sin NSScreen.main)

    private func computePanelFrame(naturalSize: CGSize?, hostWindow: NSWindow) -> NSRect {
        let winFrame = hostWindow.frame
        let screen = hostWindow.screen ?? NSScreen.screens.max(by: { a, b in
            let ia = a.frame.intersection(winFrame)
            let ib = b.frame.intersection(winFrame)
            let areaA = ia.isNull ? 0 : ia.width * ia.height
            let areaB = ib.isNull ? 0 : ib.width * ib.height
            return areaA < areaB
        }) ?? NSScreen.screens.first

        let visible = screen?.visibleFrame ?? winFrame
        let maxW = max(300, visible.width * 0.82)
        let maxH = max(240, visible.height * 0.82)

        var w: CGFloat = min(760, maxW)
        var h: CGFloat = min(560, maxH)

        if let nat = naturalSize, nat.width > 1, nat.height > 1 {
            let scale = min(maxW / nat.width, maxH / nat.height, 1.0)
            w = max(320, round(nat.width * scale))
            h = max(240, round(nat.height * scale))
            w = min(w, maxW)
            h = min(h, maxH)
        }

        let rawX = round(winFrame.midX - w / 2)
        let rawY = round(winFrame.midY - h / 2)

        let minX = visible.minX + 12
        let maxX = max(minX, visible.maxX - w - 12)
        let minY = visible.minY + 12
        let maxY = max(minY, visible.maxY - h - 12)

        let clampedX = min(max(rawX, minX), maxX)
        let clampedY = min(max(rawY, minY), maxY)

        return NSRect(x: clampedX, y: clampedY, width: w, height: h)
    }
}

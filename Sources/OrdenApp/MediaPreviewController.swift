import AppKit
import AVKit
import AVFoundation
import OrdenCore

/// Preview fiable: NSPanel + AppKit puro (sin SwiftUI hosting).
/// Imagen → NSImageView · Vídeo → AVPlayerView · Esc/clic fondo/✕ cierra.
@MainActor
final class MediaPreviewController: NSObject {
    static let shared = MediaPreviewController()

    private weak var browser: BrowserModel?
    private var panel: NSPanel?
    private var rootView: PreviewRootView?
    private var parentObservers: [NSObjectProtocol] = []
    private weak var parentWindow: NSWindow?
    private var currentEntry: FileEntry?
    private var player: AVPlayer?

    var isVisible: Bool {
        guard let panel else { return false }
        return panel.isVisible && currentEntry != nil
    }

    var currentPath: String? { currentEntry?.path }

    func bind(browser: BrowserModel) {
        self.browser = browser
    }

    /// Abrir siempre (botón ojito / Vista rápida). No toggle.
    func show(entry: FileEntry) {
        if let browser {
            browser.mediaPreviewEpoch &+= 1
            browser.mediaPreviewEntry = entry
        }
        currentEntry = entry
        ensurePanel()
        rootView?.display(entry: entry, controller: self)
        layoutPanel()
        panel?.orderFront(nil)
        parentWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        tearDownPlayer()
        currentEntry = nil
        browser?.mediaPreviewEntry = nil
        panel?.orderOut(nil)
    }

    func toggle(entry: FileEntry) {
        if isVisible, currentEntry?.id == entry.id {
            hide()
        } else {
            show(entry: entry)
        }
    }

    func resetAfterDisplayChange() {
        hide()
        layoutPanel()
    }

    func navigate(delta: Int) {
        QuickLookController.shared.navigate(delta: delta)
    }

    func openWithDefaultApp() {
        guard let path = currentEntry?.path else { return }
        if NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
            hide()
        }
    }

    // MARK: - Player (vídeo)

    func attachVideo(url: URL) {
        tearDownPlayer()
        let p = AVPlayer(url: url)
        player = p
        rootView?.setVideoPlayer(p)
        p.play()
    }

    func tearDownPlayer() {
        player?.pause()
        player = nil
        rootView?.setVideoPlayer(nil)
    }

    // MARK: - Panel

    private func ensurePanel() {
        if panel != nil {
            attachToParentIfNeeded()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let root = PreviewRootView(frame: panel.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        root.onClose = { [weak self] in self?.hide() }
        root.onPrev = { [weak self] in self?.navigate(delta: -1) }
        root.onNext = { [weak self] in self?.navigate(delta: 1) }
        root.onOpenExternal = { [weak self] in self?.openWithDefaultApp() }
        panel.contentView = root

        self.panel = panel
        self.rootView = root
        attachToParentIfNeeded()
        observeParent()
    }

    private func attachToParentIfNeeded() {
        guard let panel else { return }
        let parent = FindaroWindowRegistry.registeredWindows.first(where: \.isKeyWindow)
            ?? FindaroWindowRegistry.registeredWindows.first(where: { $0.isVisible && !$0.isMiniaturized })
            ?? NSApp.keyWindow
        guard let parent else { return }
        if parentWindow !== parent {
            parentWindow?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
            parentWindow = parent
        }
    }

    private func observeParent() {
        for o in parentObservers {
            NotificationCenter.default.removeObserver(o)
        }
        parentObservers.removeAll()
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let win = note.object as? NSWindow
                Task { @MainActor in
                    guard let self, let win, win === self.parentWindow else { return }
                    self.layoutPanel()
                }
            }
            parentObservers.append(token)
        }
    }

    private func layoutPanel() {
        guard let panel else { return }
        attachToParentIfNeeded()
        guard let parent = parentWindow ?? panel.parent else { return }
        let screenFrame: NSRect
        if let cv = parent.contentView {
            let rectInWindow = cv.convert(cv.bounds, to: nil)
            screenFrame = parent.convertToScreen(rectInWindow)
        } else {
            screenFrame = parent.frame
        }
        panel.setFrame(screenFrame, display: true)
    }
}

// MARK: - AppKit root view

private final class PreviewRootView: NSView {
    var onClose: (() -> Void)?
    var onPrev: (() -> Void)?
    var onNext: (() -> Void)?
    var onOpenExternal: (() -> Void)?

    private let dimView = NSView()
    private let chrome = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()
    private let imageView = NSImageView()
    private let playerView = AVPlayerView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "", target: nil, action: nil)
    private let mediaBox = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        addSubview(dimView)

        chrome.wantsLayer = true
        addSubview(chrome)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        chrome.addSubview(titleLabel)

        configureIconButton(prevButton, symbol: "chevron.left.circle.fill") {
            [weak self] in self?.onPrev?()
        }
        configureIconButton(nextButton, symbol: "chevron.right.circle.fill") {
            [weak self] in self?.onNext?()
        }
        configureIconButton(closeButton, symbol: "xmark.circle.fill") {
            [weak self] in self?.onClose?()
        }
        chrome.addSubview(prevButton)
        chrome.addSubview(nextButton)
        chrome.addSubview(closeButton)

        mediaBox.wantsLayer = true
        mediaBox.layer?.backgroundColor = NSColor.black.cgColor
        mediaBox.layer?.cornerRadius = 12
        mediaBox.layer?.masksToBounds = true
        chrome.addSubview(mediaBox)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        mediaBox.addSubview(imageView)

        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        playerView.wantsLayer = true
        playerView.isHidden = true
        mediaBox.addSubview(playerView)

        messageLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.alignment = .center
        messageLabel.isHidden = true
        mediaBox.addSubview(messageLabel)

        openButton.title = L10n.s("Abrir con la app predeterminada", "Open with default app")
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openExternal)
        openButton.isHidden = true
        mediaBox.addSubview(openButton)

        let click = NSClickGestureRecognizer(target: self, action: #selector(backgroundClicked(_:)))
        dimView.addGestureRecognizer(click)
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: @escaping () -> Void) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        button.symbolConfiguration = .init(pointSize: 22, weight: .regular)
        button.target = self
        button.setAccessibilityLabel(symbol)
        // Store action via associated closure through tags — use simple selectors.
        switch symbol {
        case "chevron.left.circle.fill":
            button.action = #selector(prevTapped)
        case "chevron.right.circle.fill":
            button.action = #selector(nextTapped)
        default:
            button.action = #selector(closeTapped)
        }
        _ = action
    }

    @objc private func prevTapped() { onPrev?() }
    @objc private func nextTapped() { onNext?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func openExternal() { onOpenExternal?() }

    @objc private func backgroundClicked(_ gesture: NSClickGestureRecognizer) {
        let p = gesture.location(in: self)
        if !chrome.frame.contains(p) {
            onClose?()
        }
    }

    override func layout() {
        super.layout()
        let b = bounds
        dimView.frame = b

        let maxChromeW: CGFloat = 1040
        let chromeW = min(maxChromeW, b.width - 48)
        let chromeH = min(720, b.height - 48)
        chrome.frame = NSRect(
            x: (b.width - chromeW) / 2,
            y: (b.height - chromeH) / 2,
            width: chromeW,
            height: chromeH
        )

        let pad: CGFloat = 16
        titleLabel.frame = NSRect(x: pad, y: chromeH - 40, width: chromeW - 130, height: 24)
        closeButton.frame = NSRect(x: chromeW - 40, y: chromeH - 42, width: 28, height: 28)
        nextButton.frame = NSRect(x: chromeW - 72, y: chromeH - 42, width: 28, height: 28)
        prevButton.frame = NSRect(x: chromeW - 104, y: chromeH - 42, width: 28, height: 28)

        let mediaY: CGFloat = pad
        let mediaH = max(120, chromeH - 56 - pad)
        mediaBox.frame = NSRect(x: pad, y: mediaY, width: chromeW - pad * 2, height: mediaH)
        let mb = mediaBox.bounds
        imageView.frame = mb
        playerView.frame = mb
        messageLabel.frame = NSRect(x: 24, y: mb.midY + 10, width: mb.width - 48, height: 60)
        openButton.frame = NSRect(x: (mb.width - 260) / 2, y: mb.midY - 40, width: 260, height: 32)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53, 49: // esc / space
            onClose?()
        case 123:
            onPrev?()
        case 124:
            onNext?()
        default:
            super.keyDown(with: event)
        }
    }

    func display(entry: FileEntry, controller: MediaPreviewController) {
        titleLabel.stringValue = entry.name
        imageView.isHidden = true
        playerView.isHidden = true
        messageLabel.isHidden = true
        openButton.isHidden = true
        imageView.image = nil
        controller.tearDownPlayer()

        if entry.category == .image {
            if let img = NSImage(contentsOfFile: entry.path) {
                imageView.image = img
                imageView.isHidden = false
            } else {
                imageView.image = NSWorkspace.shared.icon(forFile: entry.path)
                imageView.isHidden = false
                messageLabel.stringValue = L10n.s(
                    "No se pudo cargar la imagen completa",
                    "Couldn’t load the full image"
                )
                messageLabel.isHidden = false
            }
        } else if entry.category == .video {
            playerView.isHidden = false
            let url = URL(fileURLWithPath: entry.path)
            let asset = AVURLAsset(url: url)
            Task { @MainActor in
                do {
                    let ok = try await asset.load(.isPlayable)
                    guard controller.currentPath == entry.path else { return }
                    if ok {
                        controller.attachVideo(url: url)
                    } else {
                        self.showUnsupported(
                            L10n.s(
                                "macOS no puede previsualizar este códec aquí. Ábrelo con IINA, VLC u otro.",
                                "macOS can’t preview this codec here. Open it with IINA, VLC, or another player."
                            )
                        )
                    }
                } catch {
                    guard controller.currentPath == entry.path else { return }
                    self.showUnsupported(
                        L10n.s(
                            "No se pudo leer el vídeo. Ábrelo con tu reproductor.",
                            "Couldn’t read the video. Open it with your player."
                        )
                    )
                }
            }
        } else {
            imageView.image = NSWorkspace.shared.icon(forFile: entry.path)
            imageView.isHidden = false
            imageView.imageScaling = .scaleProportionallyDown
        }

        window?.makeFirstResponder(self)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func setVideoPlayer(_ player: AVPlayer?) {
        playerView.player = player
        if player != nil {
            playerView.isHidden = false
            messageLabel.isHidden = true
            openButton.isHidden = true
        }
    }

    private func showUnsupported(_ text: String) {
        playerView.isHidden = true
        imageView.isHidden = true
        messageLabel.stringValue = text
        messageLabel.isHidden = false
        openButton.isHidden = false
    }
}

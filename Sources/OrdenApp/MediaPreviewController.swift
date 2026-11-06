import AppKit
import AVKit
import AVFoundation
import OrdenCore

/// Vista previa propia para vídeo/imagen (no depende del icono roto de VLC/Quick Look).
@MainActor
final class MediaPreviewController: NSObject, NSWindowDelegate {
    static let shared = MediaPreviewController()

    private var window: NSWindow?
    private var playerView: AVPlayerView?
    private var imageView: NSImageView?
    private var titleLabel: NSTextField?
    private var player: AVPlayer?

    var isVisible: Bool { window?.isVisible == true }

    func show(entry: FileEntry) {
        ensureWindow()
        guard let window, let playerView, let imageView, let titleLabel else { return }
        titleLabel.stringValue = entry.name

        player?.pause()
        player = nil
        playerView.player = nil
        imageView.image = nil
        playerView.isHidden = true
        imageView.isHidden = true

        let url = URL(fileURLWithPath: entry.path)
        switch entry.category {
        case .video:
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            player = p
            playerView.player = p
            playerView.isHidden = false
            p.play()
        case .image:
            imageView.image = NSImage(contentsOf: url)
            imageView.isHidden = false
        default:
            imageView.image = NSWorkspace.shared.icon(forFile: entry.path)
            imageView.isHidden = false
        }

        window.title = entry.name
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        player?.pause()
        player = nil
        playerView?.player = nil
        window?.orderOut(nil)
    }

    func toggle(entry: FileEntry) {
        if isVisible {
            hide()
        } else {
            show(entry: entry)
        }
    }

    private func ensureWindow() {
        if window != nil { return }

        let rect = NSRect(x: 0, y: 0, width: 900, height: 620)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Vista previa"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.minSize = NSSize(width: 480, height: 320)

        let content = NSView(frame: rect)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        title.drawsBackground = false
        title.isBezeled = false
        title.translatesAutoresizingMaskIntoConstraints = false

        let pv = AVPlayerView(frame: .zero)
        pv.controlsStyle = .floating
        pv.translatesAutoresizingMaskIntoConstraints = false

        let iv = NSImageView(frame: .zero)
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(title)
        content.addSubview(pv)
        content.addSubview(iv)
        win.contentView = content

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            pv.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            pv.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pv.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pv.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            iv.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            iv.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            iv.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        window = win
        playerView = pv
        imageView = iv
        titleLabel = title
    }

    func windowWillClose(_ notification: Notification) {
        player?.pause()
        player = nil
        playerView?.player = nil
    }
}

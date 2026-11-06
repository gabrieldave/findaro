import AppKit
import SwiftUI
import OrdenCore

/// Monitor AppKit: ⌘+clic enciende modo naranja sticky; doble clic abre.
@MainActor
final class FileDragArmMonitor {
    static let shared = FileDragArmMonitor()

    private var monitor: Any?
    private weak var browser: BrowserModel?

    /// Frames de filas en coordenadas de la key window.
    private var rowFrames: [String: CGRect] = [:]

    /// Fallback si `clickCount` no llega bien (SwiftUI / eventos sintéticos).
    private var lastClickPath: String?
    private var lastClickAt: Date?

    func attach(browser: BrowserModel) {
        self.browser = browser
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown]
        ) { [weak self] event in
            // nil = tragar el evento (evita que un onTapGesture de fondo apague el naranja).
            self?.handle(event) ?? event
        }
    }

    func updateRowFrame(path: String, frameInWindow: CGRect) {
        guard !path.isEmpty, frameInWindow.width > 2, frameInWindow.height > 2 else { return }
        rowFrames[path] = frameInWindow
    }

    func removeRowFrame(path: String) {
        rowFrames.removeValue(forKey: path)
    }

    /// `nil` = consumir el evento; si no, dejarlo pasar.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let browser, event.type == .leftMouseDown else { return event }
        let path = pathAt(event.locationInWindow)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let shift = flags.contains(.shift)
        let opt = flags.contains(.option)

        let isDouble: Bool = {
            if event.clickCount >= 2 { return true }
            guard let path,
                  lastClickPath == path,
                  let last = lastClickAt,
                  Date().timeIntervalSince(last) < 0.5 else { return false }
            return true
        }()

        if isDouble, let path,
           let entry = browser.visibleEntries.first(where: { $0.path == path }) {
            lastClickPath = nil
            lastClickAt = nil
            browser.clearArmedFileDrag()
            browser.selectOnly(entry.id)
            browser.activateEntry(entry)
            return nil
        }

        lastClickPath = path
        lastClickAt = Date()

        // ⌘+clic (sin Shift/⌥): naranja sticky + multi.
        // Tragamos el clic: si pasa a SwiftUI, el tap del fondo llama cancelSelection().
        guard cmd, !shift, !opt,
              let path,
              let entry = browser.visibleEntries.first(where: { $0.path == path })
        else { return event }

        browser.armFileDrag(for: entry)
        return nil
    }

    private func pathAt(_ pointInWindow: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for (path, frame) in rowFrames where frame.contains(pointInWindow) {
            let area = frame.width * frame.height
            if best == nil || area < best!.1 {
                best = (path, area)
            }
        }
        if let best { return best.0 }

        var bandHit: (String, CGFloat)?
        for (path, frame) in rowFrames where pointInWindow.y >= frame.minY && pointInWindow.y <= frame.maxY {
            let dx = abs(frame.midX - pointInWindow.x)
            if bandHit == nil || dx < bandHit!.1 {
                bandHit = (path, dx)
            }
        }
        return bandHit?.0
    }
}

/// NSView que reporta su frame en coordenadas de ventana al monitor.
private final class FileDragArmFrameNSView: NSView {
    var path: String = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postsFrameChangedNotifications = true
        postsBoundsChangedNotifications = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        report()
    }

    override func layout() {
        super.layout()
        report()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        report()
    }

    private func report() {
        guard !path.isEmpty, window != nil, !bounds.isEmpty else { return }
        let rect = convert(bounds, to: nil)
        let p = path
        // Síncrono en main: si va en Task, el primer ⌘+clic no encuentra frame.
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                FileDragArmMonitor.shared.updateRowFrame(path: p, frameInWindow: rect)
            }
        } else {
            DispatchQueue.main.async {
                FileDragArmMonitor.shared.updateRowFrame(path: p, frameInWindow: rect)
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, !path.isEmpty {
            let p = path
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    FileDragArmMonitor.shared.removeRowFrame(path: p)
                }
            } else {
                DispatchQueue.main.async {
                    FileDragArmMonitor.shared.removeRowFrame(path: p)
                }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

private struct FileDragArmFrameReader: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> FileDragArmFrameNSView {
        let v = FileDragArmFrameNSView()
        v.path = path
        return v
    }

    func updateNSView(_ nsView: FileDragArmFrameNSView, context: Context) {
        nsView.path = path
        DispatchQueue.main.async {
            nsView.needsLayout = true
            nsView.layoutSubtreeIfNeeded()
        }
    }
}

extension View {
    func reportFileDragArmFrame(path: String) -> some View {
        background(FileDragArmFrameReader(path: path))
            .onDisappear {
                FileDragArmMonitor.shared.removeRowFrame(path: path)
            }
    }

    func enableFileDragArmMonitor(browser: BrowserModel) -> some View {
        onAppear { FileDragArmMonitor.shared.attach(browser: browser) }
    }

    /// Doble clic por fila (carpetas y archivos) — no depende de frames AppKit.
    func fileOpenOnDoubleClick(entry: FileEntry, browser: BrowserModel) -> some View {
        simultaneousGesture(
            TapGesture(count: 2).onEnded {
                browser.selectOnly(entry.id)
                browser.activateEntry(entry)
            }
        )
    }
}

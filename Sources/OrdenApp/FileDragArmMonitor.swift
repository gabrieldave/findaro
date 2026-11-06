import AppKit
import SwiftUI
import OrdenCore

/// Monitor AppKit: hold 1s + doble clic sin pelear con el marquee de SwiftUI.
@MainActor
final class FileDragArmMonitor {
    static let shared = FileDragArmMonitor()

    private var monitor: Any?
    private var downPoint: CGPoint?
    private var downTime: Date?
    private var tickTimer: Timer?
    private weak var browser: BrowserModel?

    /// Solo cancelamos/armamos desde el monitor si el mouseDown cayó en una fila conocida.
    private var monitorOwnedPress = false

    /// Frames de filas en coordenadas de la key window.
    private var rowFrames: [String: CGRect] = [:]

    /// Fallback si `clickCount` no llega bien (SwiftUI / eventos sintéticos).
    private var lastClickPath: String?
    private var lastClickAt: Date?

    func attach(browser: BrowserModel) {
        self.browser = browser
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func updateRowFrame(path: String, frameInWindow: CGRect) {
        guard !path.isEmpty, frameInWindow.width > 2, frameInWindow.height > 2 else { return }
        rowFrames[path] = frameInWindow
    }

    func removeRowFrame(path: String) {
        rowFrames.removeValue(forKey: path)
    }

    private func handle(_ event: NSEvent) {
        guard let browser else { return }
        switch event.type {
        case .leftMouseDown:
            let path = pathAt(event.locationInWindow)
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
                cancelMonitorPress(clearArming: true)
                lastClickPath = nil
                lastClickAt = nil
                browser.selectOnly(entry.id)
                browser.activateEntry(entry)
                return
            }

            lastClickPath = path
            lastClickAt = Date()

            downPoint = event.locationInWindow
            downTime = Date()
            tickTimer?.invalidate()
            tickTimer = nil
            monitorOwnedPress = false

            if let path,
               let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                monitorOwnedPress = true
                browser.beginArmingFileDrag(for: entry)
                tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
            }

        case .leftMouseDragged:
            // No tocar el armado que inició el gesto SwiftUI de la fila.
            guard monitorOwnedPress, let origin = downPoint else { return }
            let p = event.locationInWindow
            let dist = hypot(p.x - origin.x, p.y - origin.y)
            if dist > FileDragArmChrome.maxWiggle, !browser.hasArmedFileDrag {
                cancelMonitorPress(clearArming: true)
            }

        case .leftMouseUp:
            if monitorOwnedPress {
                if let path = browser.fileDragArmingPath,
                   let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                    browser.endArmingPress(for: entry)
                }
            }
            cancelMonitorPress(clearArming: false)

        default:
            break
        }
    }

    private func tick() {
        guard monitorOwnedPress,
              let browser,
              let start = downTime,
              browser.fileDragArmingPath != nil else { return }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed >= FileDragArmChrome.holdDuration {
            if let path = browser.fileDragArmingPath,
               let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                browser.armFileDrag(for: entry)
            }
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func cancelMonitorPress(clearArming: Bool) {
        tickTimer?.invalidate()
        tickTimer = nil
        if clearArming, monitorOwnedPress, let browser {
            if let path = browser.fileDragArmingPath,
               let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                browser.endArmingPress(for: entry)
            }
        }
        monitorOwnedPress = false
        downPoint = nil
        downTime = nil
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
        Task { @MainActor in
            FileDragArmMonitor.shared.updateRowFrame(path: path, frameInWindow: rect)
        }
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

import AppKit
import SwiftUI
import OrdenCore

/// Monitor AppKit: ⌘+clic enciende modo naranja sticky; doble clic abre.
@MainActor
final class FileDragArmMonitor {
    static let shared = FileDragArmMonitor()

    private var monitor: Any?
    private weak var browser: BrowserModel?

    /// Frames de filas en coordenadas de la key window (path → rect).
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
        guard !path.isEmpty else { return }
        rowFrames.removeValue(forKey: path)
    }

    /// `nil` = consumir el evento; si no, dejarlo pasar.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let browser, event.type == .leftMouseDown else { return event }
        pruneStaleFrames()
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

        // ⌘+clic (sin Shift/⌥): naranja sticky + multi (suma/quita 1).
        // Tragamos el clic: si pasa a SwiftUI, el tap del fondo llama cancelSelection().
        guard cmd, !shift, !opt,
              let path,
              let entry = browser.visibleEntries.first(where: { $0.path == path })
        else { return event }

        // Mismo rango que ⇧+clic, en modo naranja para mover.
        browser.commandRangeSelectForMove(to: entry.id)
        return nil
    }

    /// Quita frames de paths que ya no están en la lista visible (LazyVStack recicla mal).
    private func pruneStaleFrames() {
        guard let browser else {
            rowFrames.removeAll()
            return
        }
        let live = Set(browser.visibleEntries.map(\.path))
        if rowFrames.keys.contains(where: { !live.contains($0) }) {
            rowFrames = rowFrames.filter { live.contains($0.key) }
        }
    }

    /// Elige la fila cuyo centro está más cerca del clic (no el frame “más chico”).
    /// Así no arma el vecino cuando hay frames viejos o solapados.
    private func pathAt(_ pointInWindow: CGPoint) -> String? {
        var bestInside: (path: String, score: CGFloat)?
        for (path, frame) in rowFrames where frame.insetBy(dx: 0, dy: 1).contains(pointInWindow) {
            let dy = abs(frame.midY - pointInWindow.y)
            let dx = abs(frame.midX - pointInWindow.x)
            let score = dy * 10_000 + dx
            if bestInside == nil || score < bestInside!.score {
                bestInside = (path, score)
            }
        }
        if let bestInside { return bestInside.path }

        // Casi en la fila (borde): misma métrica, con tolerancia vertical corta.
        var bestNear: (path: String, score: CGFloat)?
        for (path, frame) in rowFrames {
            guard pointInWindow.x >= frame.minX - 4, pointInWindow.x <= frame.maxX + 4 else { continue }
            let dy = abs(frame.midY - pointInWindow.y)
            guard dy <= max(14, frame.height * 0.5) else { continue }
            let score = dy * 10_000 + abs(frame.midX - pointInWindow.x)
            if bestNear == nil || score < bestNear!.score {
                bestNear = (path, score)
            }
        }
        return bestNear?.path
    }
}

/// NSView que reporta su frame en coordenadas de ventana al monitor.
private final class FileDragArmFrameNSView: NSView {
    private var trackedPath: String = ""

    var path: String {
        get { trackedPath }
        set {
            let old = trackedPath
            guard old != newValue else { return }
            if !old.isEmpty {
                FileDragArmMonitor.shared.removeRowFrame(path: old)
            }
            trackedPath = newValue
            report()
        }
    }

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

    fileprivate func report() {
        guard !trackedPath.isEmpty, window != nil, !bounds.isEmpty else { return }
        let rect = convert(bounds, to: nil)
        let p = trackedPath
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
        if newWindow == nil, !trackedPath.isEmpty {
            let p = trackedPath
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
            nsView.report()
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

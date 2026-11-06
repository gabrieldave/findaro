import AppKit
import SwiftUI
import OrdenCore

/// Monitor AppKit: hold 1s sin pelear con el marquee de SwiftUI.
@MainActor
final class FileDragArmMonitor {
    static let shared = FileDragArmMonitor()

    private var monitor: Any?
    private var downPoint: CGPoint?
    private var downTime: Date?
    private var tickTimer: Timer?
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
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func updateRowFrame(path: String, frameInWindow: CGRect) {
        guard !path.isEmpty else { return }
        rowFrames[path] = frameInWindow
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
                      Date().timeIntervalSince(last) < 0.45 else { return false }
                return true
            }()

            if isDouble, let path,
               let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                cancelArming()
                lastClickPath = nil
                lastClickAt = nil
                browser.selectOnly(entry.id)
                browser.activateEntry(entry)
                downPoint = nil
                downTime = nil
                return
            }

            lastClickPath = path
            lastClickAt = Date()

            downPoint = event.locationInWindow
            downTime = Date()
            tickTimer?.invalidate()
            tickTimer = nil
            if let path,
               let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                browser.beginArmingFileDrag(for: entry)
                tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
            }

        case .leftMouseDragged:
            guard let origin = downPoint else { return }
            let p = event.locationInWindow
            let dist = hypot(p.x - origin.x, p.y - origin.y)
            if dist > FileDragArmChrome.maxWiggle, !browser.hasArmedFileDrag {
                cancelArming()
            }

        case .leftMouseUp:
            if !browser.hasArmedFileDrag {
                if let path = browser.fileDragArmingPath,
                   let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                    browser.endArmingPress(for: entry)
                }
            } else {
                // Deja el banner "Listo" unos segundos; solo quita el anillo.
                if let path = browser.fileDragArmingPath,
                   let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                    browser.endArmingPress(for: entry)
                }
            }
            downPoint = nil
            downTime = nil
            tickTimer?.invalidate()
            tickTimer = nil

        default:
            break
        }
    }

    private func tick() {
        guard let browser, let start = downTime, browser.fileDragArmingPath != nil else { return }
        let elapsed = Date().timeIntervalSince(start)
        // El anillo ya lo anima beginArming; aquí forzamos el armado al cumplir 1s.
        if elapsed >= FileDragArmChrome.holdDuration {
            if let path = browser.fileDragArmingPath,
               let entry = browser.visibleEntries.first(where: { $0.path == path }) {
                browser.armFileDrag(for: entry)
            }
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func cancelArming() {
        tickTimer?.invalidate()
        tickTimer = nil
        guard let browser else { return }
        if let path = browser.fileDragArmingPath,
           let entry = browser.visibleEntries.first(where: { $0.path == path }) {
            browser.endArmingPress(for: entry)
        }
        downPoint = nil
        downTime = nil
    }

    private func pathAt(_ pointInWindow: CGPoint) -> String? {
        // Preferir el frame más pequeño que contenga el punto (celdas anidadas).
        var best: (String, CGFloat)?
        for (path, frame) in rowFrames where frame.contains(pointInWindow) {
            let area = frame.width * frame.height
            if best == nil || area < best!.1 {
                best = (path, area)
            }
        }
        return best?.0
    }
}

/// NSView que reporta su frame en coordenadas de ventana al monitor.
private final class FileDragArmFrameNSView: NSView {
    var path: String = ""

    override func layout() {
        super.layout()
        report()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    private func report() {
        guard !path.isEmpty, window != nil, !bounds.isEmpty else { return }
        let rect = convert(bounds, to: nil)
        FileDragArmMonitor.shared.updateRowFrame(path: path, frameInWindow: rect)
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
        DispatchQueue.main.async { nsView.layout() }
    }
}

extension View {
    func reportFileDragArmFrame(path: String) -> some View {
        background(FileDragArmFrameReader(path: path))
    }

    func enableFileDragArmMonitor(browser: BrowserModel) -> some View {
        onAppear { FileDragArmMonitor.shared.attach(browser: browser) }
    }
}

import AppKit
import SwiftUI
import OrdenCore

/// Monitor AppKit que registra las teclas (⌘/⇧) de cada clic para la selección múltiple.
/// El doble clic para abrir lo maneja SwiftUI en cada fila (`fileOpenOnDoubleClick`):
/// los frames AppKit del LazyVStack se quedan stale tras scroll y abrían la fila equivocada.
@MainActor
final class FileDragArmMonitor {
    static let shared = FileDragArmMonitor()

    private var monitor: Any?
    private weak var browser: BrowserModel?

    private var rowFrames: [String: RowHitTestLogic.RowFrame] = [:]
    /// Sube en cada scroll / cambio de lista — invalida frames viejos del LazyVStack.
    private(set) var frameGeneration: UInt64 = 1

    func attach(browser: BrowserModel) {
        self.browser = browser
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    /// Llamar al hacer scroll o al cambiar `visibleEntries`.
    func invalidateFrames() {
        frameGeneration &+= 1
        rowFrames.removeAll(keepingCapacity: true)
    }

    func updateRowFrame(path: String, frameInWindow: CGRect) {
        guard !path.isEmpty, frameInWindow.width > 2, frameInWindow.height > 2 else { return }
        rowFrames[path] = RowHitTestLogic.RowFrame(
            path: path,
            frame: frameInWindow,
            generation: frameGeneration
        )
    }

    func removeRowFrame(path: String) {
        guard !path.isEmpty else { return }
        rowFrames.removeValue(forKey: path)
    }

    /// Teclas pulsadas en el último mouseDown (ver `ClickModifierMemory`).
    private(set) var clickMemory = ClickModifierMemory()

    /// Teclas efectivas del clic que SwiftUI está procesando ahora.
    func effectiveClickModifiers() -> ClickModifierMemory.Modifiers {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let current = ClickModifierMemory.Modifiers(
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option)
        )
        return clickMemory.resolve(
            now: ProcessInfo.processInfo.systemUptime,
            current: current,
            window: ClickModifierMemory.window(doubleClickInterval: NSEvent.doubleClickInterval)
        )
    }

    /// Solo REGISTRA las teclas del clic; nunca se come el evento.
    /// Antes este monitor resolvía ⌘+clic con frames AppKit de las filas: tras hacer scroll los
    /// frames quedaban viejos (o eran de otra ventana con la misma carpeta) y el ⌘+clic se
    /// aplicaba a otro archivo o se perdía. Ahora la selección la decide SIEMPRE la fila SwiftUI
    /// pulsada, con las teclas capturadas aquí en el mouseDown.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .leftMouseDown else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        clickMemory.recordMouseDown(
            ClickModifierMemory.Modifiers(
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                option: flags.contains(.option)
            ),
            at: event.timestamp
        )
        return event
    }

    private func pruneStaleFrames() {
        guard let browser else {
            rowFrames.removeAll()
            return
        }
        var live = Set(browser.visibleEntries.map(\.path))
        if browser.dualPaneEnabled {
            live.formUnion(browser.secondaryEntries.map(\.path))
        }
        let gen = frameGeneration
        rowFrames = rowFrames.filter { live.contains($0.key) && $0.value.generation == gen }
    }

    private func pathAt(_ pointInWindow: CGPoint) -> String? {
        RowHitTestLogic.pathAt(
            point: pointInWindow,
            frames: Array(rowFrames.values),
            generation: frameGeneration
        )
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

    /// Doble clic ligado a la fila SwiftUI (no a frames AppKit).
    func fileOpenOnDoubleClick(entry: FileEntry, browser: BrowserModel) -> some View {
        highPriorityGesture(
            TapGesture(count: 2).onEnded {
                browser.selectOnly(entry.id)
                browser.activateEntry(entry)
            }
        )
    }
}

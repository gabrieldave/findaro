import AppKit
import SwiftUI
import OrdenCore

/// Hit zones estilo Finder:
/// - `name`: icono + nombre → clic selecciona y el jalón mueve.
/// - `row`: resto de la fila (fechas, tamaño, padding) → clic selecciona; el jalón es marquesina.
@MainActor
final class FileDragArmMonitor {
    static let shared = FileDragArmMonitor()

    enum HitKind: Equatable {
        case name
        case row
    }

    private var monitor: Any?
    private weak var browser: BrowserModel?

    private var nameFrames: [String: RowHitTestLogic.RowFrame] = [:]
    private var rowFrames: [String: RowHitTestLogic.RowFrame] = [:]
    private(set) var frameGeneration: UInt64 = 1

    private var pressPath: String?
    private var pressPoint: CGPoint?
    private var pressIsSecondary = false
    private var didStartNativeDrag = false

    var hasStartedNativeDrag: Bool { didStartNativeDrag }

    /// True si el último mouseDown armó drag de archivo (estaba sobre el nombre).
    private(set) var pressArmedFileDrag = false

    func attach(browser: BrowserModel) {
        self.browser = browser
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func invalidateFrames() {
        frameGeneration &+= 1
        nameFrames.removeAll(keepingCapacity: true)
        rowFrames.removeAll(keepingCapacity: true)
    }

    func updateHitFrame(path: String, kind: HitKind, frameInWindow: CGRect) {
        guard !path.isEmpty, frameInWindow.width > 2, frameInWindow.height > 2 else { return }
        let frame = RowHitTestLogic.RowFrame(
            path: path,
            frame: frameInWindow,
            generation: frameGeneration
        )
        switch kind {
        case .name: nameFrames[path] = frame
        case .row: rowFrames[path] = frame
        }
    }

    func removeHitFrame(path: String, kind: HitKind) {
        guard !path.isEmpty else { return }
        switch kind {
        case .name: nameFrames.removeValue(forKey: path)
        case .row: rowFrames.removeValue(forKey: path)
        }
    }

    /// Compat: frames de drag = zona nombre.
    func updateRowFrame(path: String, frameInWindow: CGRect) {
        updateHitFrame(path: path, kind: .name, frameInWindow: frameInWindow)
    }

    func removeRowFrame(path: String) {
        removeHitFrame(path: path, kind: .name)
        removeHitFrame(path: path, kind: .row)
    }

    private(set) var clickMemory = ClickModifierMemory()
    private var lastMouseDownClickCount: Int = 1
    private var lastMouseDownAt: TimeInterval = 0

    func currentClickCount() -> Int {
        if let event = NSApp.currentEvent,
           event.type == .leftMouseUp || event.type == .leftMouseDown {
            return max(1, event.clickCount)
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMouseDownAt <= NSEvent.doubleClickInterval + 0.5 else { return 1 }
        return max(1, lastMouseDownClickCount)
    }

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

    /// ¿El punto de ventana cae sobre icono+nombre?
    func isNameHit(atWindowPoint point: CGPoint) -> Bool {
        pruneStaleFrames()
        return pathAt(point, in: nameFrames) != nil
    }

    /// Path bajo el punto: prioriza nombre; si no, fila completa.
    func pathHit(atWindowPoint point: CGPoint) -> (path: String, kind: HitKind)? {
        pruneStaleFrames()
        if let p = pathAt(point, in: nameFrames) { return (p, .name) }
        if let p = pathAt(point, in: rowFrames) { return (p, .row) }
        return nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            return handleMouseDown(event)
        case .leftMouseDragged:
            return handleMouseDragged(event)
        case .leftMouseUp:
            pressPath = nil
            pressPoint = nil
            pressIsSecondary = false
            pressArmedFileDrag = false
            didStartNativeDrag = false
            return event
        default:
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        clickMemory.recordMouseDown(
            ClickModifierMemory.Modifiers(
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                option: flags.contains(.option)
            ),
            at: event.timestamp
        )
        lastMouseDownClickCount = event.clickCount
        lastMouseDownAt = event.timestamp
        pressPath = nil
        pressPoint = nil
        pressIsSecondary = false
        pressArmedFileDrag = false
        didStartNativeDrag = false

        guard event.clickCount == 1, let browser else { return event }
        pruneStaleFrames()
        guard let hit = pathHit(atWindowPoint: event.locationInWindow) else { return event }

        let path = hit.path
        let inPrimary = browser.visibleEntries.contains(where: { $0.path == path })
        let inSecondary = browser.dualPaneEnabled
            && browser.secondaryEntries.contains(where: { $0.path == path })
        let useSecondary = inSecondary && (!inPrimary || browser.focusedPane == .secondary)

        // Clic al mouseDown: ⌘/⇧/Modo varios vía clickSelect* (antes selectOnly ignoraba «Varios»).
        // noteCommandClickHandled evita que el TapGesture SwiftUI vuelva a toggleear (quita lo que sumó).
        if useSecondary {
            browser.clickSelectSecondary(path)
            browser.noteCommandClickHandled()
            if hit.kind == .name {
                pressPath = path
                pressPoint = event.locationInWindow
                pressIsSecondary = true
                pressArmedFileDrag = true
            }
        } else if inPrimary {
            browser.clickSelect(path)
            browser.noteCommandClickHandled()
            if hit.kind == .name {
                pressPath = path
                pressPoint = event.locationInWindow
                pressIsSecondary = false
                pressArmedFileDrag = true
            }
        }
        return event
    }

    private func handleMouseDragged(_ event: NSEvent) -> NSEvent {
        guard !didStartNativeDrag,
              pressArmedFileDrag,
              let path = pressPath,
              let start = pressPoint,
              let browser
        else { return event }

        let loc = event.locationInWindow
        let dist = hypot(loc.x - start.x, loc.y - start.y)
        guard dist >= PressDragSelectLogic.moveThreshold else { return event }

        let paths: [String]
        if pressIsSecondary {
            if browser.secondarySelectedIDs.contains(path), browser.secondarySelectedIDs.count > 1 {
                paths = browser.secondarySelectedEntries.map(\.path)
            } else {
                paths = [path]
            }
        } else if browser.selectedIDs.contains(path), browser.selectedIDs.count > 1 {
            paths = browser.selectedEntries.map(\.path)
        } else {
            paths = [path]
        }

        requestNativeDrag(paths: paths, deferToNextRunLoop: false)
        return event
    }

    func requestNativeDrag(paths: [String], deferToNextRunLoop: Bool = true) {
        guard !didStartNativeDrag, !paths.isEmpty, let browser else { return }
        didStartNativeDrag = true
        pressPath = nil
        pressPoint = nil
        pressArmedFileDrag = false
        let copy = paths
        let start = {
            guard NSEvent.pressedMouseButtons & (1 << 0) != 0 else { return }
            _ = browser.startDragWithPaths(copy)
        }
        if deferToNextRunLoop {
            DispatchQueue.main.async(execute: start)
        } else {
            start()
        }
    }

    private func pruneStaleFrames() {
        guard let browser else {
            nameFrames.removeAll()
            rowFrames.removeAll()
            return
        }
        var live = Set(browser.visibleEntries.map(\.path))
        if browser.dualPaneEnabled {
            live.formUnion(browser.secondaryEntries.map(\.path))
        }
        let gen = frameGeneration
        nameFrames = nameFrames.filter { live.contains($0.key) && $0.value.generation == gen }
        rowFrames = rowFrames.filter { live.contains($0.key) && $0.value.generation == gen }
    }

    private func pathAt(_ point: CGPoint, in frames: [String: RowHitTestLogic.RowFrame]) -> String? {
        RowHitTestLogic.pathAt(
            point: point,
            frames: Array(frames.values),
            generation: frameGeneration
        )
    }
}

// MARK: - Frame reporters

private final class FileHitFrameNSView: NSView {
    private var trackedPath: String = ""
    var kind: FileDragArmMonitor.HitKind = .name

    var path: String {
        get { trackedPath }
        set {
            let old = trackedPath
            guard old != newValue else { return }
            if !old.isEmpty {
                FileDragArmMonitor.shared.removeHitFrame(path: old, kind: kind)
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
        let k = kind
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                FileDragArmMonitor.shared.updateHitFrame(path: p, kind: k, frameInWindow: rect)
            }
        } else {
            DispatchQueue.main.async {
                FileDragArmMonitor.shared.updateHitFrame(path: p, kind: k, frameInWindow: rect)
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, !trackedPath.isEmpty {
            let p = trackedPath
            let k = kind
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    FileDragArmMonitor.shared.removeHitFrame(path: p, kind: k)
                }
            } else {
                DispatchQueue.main.async {
                    FileDragArmMonitor.shared.removeHitFrame(path: p, kind: k)
                }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

private struct FileHitFrameReader: NSViewRepresentable {
    let path: String
    let kind: FileDragArmMonitor.HitKind

    func makeNSView(context: Context) -> FileHitFrameNSView {
        let v = FileHitFrameNSView()
        v.kind = kind
        v.path = path
        return v
    }

    func updateNSView(_ nsView: FileHitFrameNSView, context: Context) {
        nsView.kind = kind
        nsView.path = path
    }
}

extension View {
    /// Zona icono+nombre: jalón = mover (Finder).
    func reportFileDragArmFrame(path: String) -> some View {
        background(FileHitFrameReader(path: path, kind: .name))
            .onDisappear {
                FileDragArmMonitor.shared.removeHitFrame(path: path, kind: .name)
            }
    }

    /// Fila completa: clic selecciona; jalón fuera del nombre = marquesina.
    func reportFileRowSelectFrame(path: String) -> some View {
        background(FileHitFrameReader(path: path, kind: .row))
            .onDisappear {
                FileDragArmMonitor.shared.removeHitFrame(path: path, kind: .row)
            }
    }

    func enableFileDragArmMonitor(browser: BrowserModel) -> some View {
        onAppear { FileDragArmMonitor.shared.attach(browser: browser) }
    }

    func fileOpenOnDoubleClick(entry: FileEntry, browser: BrowserModel) -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                guard FileDragArmMonitor.shared.currentClickCount() == 2 else { return }
                let mods = FileDragArmMonitor.shared.effectiveClickModifiers()
                guard !mods.command, !mods.shift else { return }
                browser.selectOnly(entry.id)
                browser.activateEntry(entry)
            }
        )
    }
}

import AppKit
import SwiftUI

/// Reporta el tamaño real del contenedor en cada resize de ventana / layout.
/// SwiftUI a veces no invalida hijos (sidebar, grilla) hasta un cambio de estado
/// como cambiar el modo de vista — este probe fuerza la actualización.
struct WindowLayoutProbe: NSViewRepresentable {
    var onChange: (CGSize) -> Void
    var onLiveResizeEnd: ((CGSize) -> Void)?

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        view.onLiveResizeEnd = onLiveResizeEnd
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = onChange
        nsView.onLiveResizeEnd = onLiveResizeEnd
        nsView.reportIfNeeded(force: true)
    }

    final class ProbeView: NSView {
        var onChange: ((CGSize) -> Void)?
        var onLiveResizeEnd: ((CGSize) -> Void)?
        private var last: CGSize = .zero

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            postsFrameChangedNotifications = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            reportIfNeeded(force: true)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            // Observamos vía NotificationCenter con selector (sin deinit Sendable issues)
            NotificationCenter.default.removeObserver(self)
            if let newWindow {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidResize(_:)),
                    name: NSWindow.didResizeNotification,
                    object: newWindow
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidEndLiveResize(_:)),
                    name: NSWindow.didEndLiveResizeNotification,
                    object: newWindow
                )
            }
        }

        @objc private func windowDidResize(_ note: Notification) {
            reportIfNeeded(force: true)
        }

        @objc private func windowDidEndLiveResize(_ note: Notification) {
            reportIfNeeded(force: true)
            let size = last.width > 1
                ? last
                : (window?.contentView?.bounds.size ?? .zero)
            onLiveResizeEnd?(size)
        }

        override func layout() {
            super.layout()
            reportIfNeeded(force: false)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            reportIfNeeded(force: false)
        }

        func reportIfNeeded(force: Bool) {
            let size: CGSize
            if let content = window?.contentView?.bounds.size, content.width > 1 {
                size = content
            } else {
                size = bounds.size
            }
            guard size.width > 1, size.height > 1 else { return }
            if !force, abs(size.width - last.width) < 0.5, abs(size.height - last.height) < 0.5 {
                return
            }
            last = size
            onChange?(size)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private struct RootLayoutWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Ancho del contenedor vía PreferenceKey (complementa el probe AppKit).
    func readLayoutWidth(_ onWidth: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: RootLayoutWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(RootLayoutWidthKey.self, perform: onWidth)
    }
}

// MARK: - Environment: ancho disponible para el panel de archivos

private struct OrdenWindowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct OrdenLayoutGenerationKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {
    var ordenWindowWidth: CGFloat {
        get { self[OrdenWindowWidthKey.self] }
        set { self[OrdenWindowWidthKey.self] = newValue }
    }

    var ordenLayoutGeneration: Int {
        get { self[OrdenLayoutGenerationKey.self] }
        set { self[OrdenLayoutGenerationKey.self] = newValue }
    }
}

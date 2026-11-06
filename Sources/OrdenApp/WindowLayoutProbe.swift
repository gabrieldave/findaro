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
        private var resizeObserver: NSObjectProtocol?
        private var endResizeObserver: NSObjectProtocol?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            postsFrameChangedNotifications = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearObservers()
            guard let window else { return }

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportIfNeeded(force: true)
                }
            }
            endResizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.reportIfNeeded(force: true)
                    let size = self.last.width > 1
                        ? self.last
                        : (self.window?.contentView?.bounds.size ?? .zero)
                    self.onLiveResizeEnd?(size)
                }
            }
            reportIfNeeded(force: true)
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

        private func clearObservers() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            if let endResizeObserver {
                NotificationCenter.default.removeObserver(endResizeObserver)
                self.endResizeObserver = nil
            }
        }

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
            if let endResizeObserver {
                NotificationCenter.default.removeObserver(endResizeObserver)
            }
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

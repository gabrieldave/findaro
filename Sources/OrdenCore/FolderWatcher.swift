import Foundation

/// Observa altas/bajas/renombres en una carpeta (no subárbol) con debounce.
public final class FolderWatcher: @unchecked Sendable {
    public var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var watchedPath: String?
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.ordena.folder-watcher")

    public init() {}

    deinit {
        stop()
    }

    /// Si ya mira la misma ruta, no reinicia el descriptor (evita bucles al recargar).
    public func watch(path: String) {
        let standardized = (path as NSString).standardizingPath
        if watchedPath == standardized, source != nil { return }
        stop()
        let fd = open(standardized, O_EVTONLY)
        guard fd >= 0 else { return }
        dirFD = fd
        watchedPath = standardized
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke, .link],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.scheduleNotify()
        }
        src.setCancelHandler { [weak self] in
            if let self, self.dirFD >= 0 {
                close(self.dirFD)
                self.dirFD = -1
            }
        }
        source = src
        src.resume()
    }

    public func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        source?.cancel()
        source = nil
        watchedPath = nil
    }

    private func scheduleNotify() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + .milliseconds(400), execute: work)
    }
}

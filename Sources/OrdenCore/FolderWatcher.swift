import Foundation

/// Observa cambios en una carpeta (y un nivel de hijos) y notifica con debounce.
public final class FolderWatcher: @unchecked Sendable {
    public var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.ordena.folder-watcher")
    private let debounceNanos: UInt64 = 350_000_000

    public init() {}

    deinit {
        stop()
    }

    public func watch(path: String) {
        stop()
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        dirFD = fd
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
    }

    private func scheduleNotify() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + .milliseconds(350), execute: work)
    }
}

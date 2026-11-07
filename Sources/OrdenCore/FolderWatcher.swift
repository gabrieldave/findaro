import Foundation
import CoreServices

/// Observa cambios en una carpeta con FSEvents y agrupa escrituras consecutivas
/// para refrescar el explorador poco después de que termine una descarga.
public final class FolderWatcher: @unchecked Sendable {
    public var onChange: (() -> Void)?

    private var stream: FSEventStreamRef?
    private var watchedPath: String?
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.ordena.folder-watcher")
    private let stateLock = NSLock()

    private let eventLatency: CFTimeInterval = 0.15
    private let debounceMilliseconds = 220

    public init() {}

    deinit {
        stop()
    }

    public func watch(path: String) {
        let standardized = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path

        if watchedPath == standardized, stream != nil { return }
        stop()

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir),
              isDir.boolValue else { return }

        watchedPath = standardized
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [standardized] as CFArray
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let created = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleNotify()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            eventLatency,
            flags
        ) else {
            watchedPath = nil
            return
        }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            stream = nil
            watchedPath = nil
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
    }

    public func stop() {
        stateLock.lock()
        debounceWork?.cancel()
        debounceWork = nil
        stateLock.unlock()

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        watchedPath = nil
    }

    private func scheduleNotify() {
        stateLock.lock()
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWork = work
        stateLock.unlock()

        queue.asyncAfter(
            deadline: .now() + .milliseconds(debounceMilliseconds),
            execute: work
        )
    }
}

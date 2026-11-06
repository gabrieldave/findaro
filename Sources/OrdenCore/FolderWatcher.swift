import Foundation
import CoreServices

/// Observa cambios en una carpeta con FSEvents (más fiable que DispatchSource en macOS).
public final class FolderWatcher: @unchecked Sendable {
    public var onChange: (() -> Void)?

    private var stream: FSEventStreamRef?
    private var watchedPath: String?
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.ordena.folder-watcher")

    public init() {}

    deinit {
        stop()
    }

    public func watch(path: String) {
        let standardized = (path as NSString).standardizingPath
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
            0.35,
            flags
        ) else { return }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    public func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        watchedPath = nil
    }

    private func scheduleNotify() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + .milliseconds(450), execute: work)
    }
}

import Foundation
import CoreServices

/// Observa cambios en una carpeta con FSEvents y agrupa escrituras consecutivas
/// para refrescar el explorador poco después de que termine una descarga.
///
/// Estrategia de notificación:
/// - **Leading**: el primer evento de un burst dispara un aviso rápido (~50 ms)
///   para que un archivo nuevo (p. ej. `.crdownload`) aparezca al instante.
/// - **Trailing**: cada evento posterior reinicia un debounce (~180 ms) para
///   consolidar renombres/finales de descarga sin parpadear.
/// - **Max interval**: si la escritura es continua (descarga larga), fuerza un
///   refresco al menos cada ~700 ms para no “perder” el progreso en UI.
public final class FolderWatcher: @unchecked Sendable {
    public var onChange: (() -> Void)?

    private var stream: FSEventStreamRef?
    private var watchedPath: String?
    private var trailingWork: DispatchWorkItem?
    private var leadingWork: DispatchWorkItem?
    private var burstStartedAt: Date?
    private var lastFiredAt: Date?
    private let queue = DispatchQueue(label: "app.ordena.folder-watcher")
    private let stateLock = NSLock()

    private let eventLatency: CFTimeInterval = 0.1
    private let leadingMilliseconds = 50
    private let trailingMilliseconds = 180
    private let maxIntervalMilliseconds = 700

    public init() {}

    deinit {
        stop()
    }

    public func watch(path: String) {
        let standardized = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path

        stateLock.lock()
        let alreadyWatching = watchedPath == standardized && stream != nil
        stateLock.unlock()
        if alreadyWatching { return }

        stop()

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir),
              isDir.boolValue else { return }

        stateLock.lock()
        watchedPath = standardized
        stateLock.unlock()

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
            stateLock.lock()
            watchedPath = nil
            stateLock.unlock()
            return
        }

        stateLock.lock()
        stream = created
        stateLock.unlock()

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            stateLock.lock()
            stream = nil
            watchedPath = nil
            stateLock.unlock()
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
    }

    public func stop() {
        stateLock.lock()
        trailingWork?.cancel()
        trailingWork = nil
        leadingWork?.cancel()
        leadingWork = nil
        burstStartedAt = nil
        let existing = stream
        stream = nil
        watchedPath = nil
        stateLock.unlock()

        if let existing {
            FSEventStreamStop(existing)
            FSEventStreamInvalidate(existing)
            FSEventStreamRelease(existing)
        }
    }

    private func scheduleNotify() {
        stateLock.lock()
        let now = Date()
        let isNewBurst = burstStartedAt == nil
        if isNewBurst {
            burstStartedAt = now
        }

        let burstAgeMs = (burstStartedAt.map { now.timeIntervalSince($0) } ?? 0) * 1000
        let sinceLastFireMs = (lastFiredAt.map { now.timeIntervalSince($0) } ?? .infinity) * 1000
        let needsForcedRefresh = burstAgeMs >= Double(maxIntervalMilliseconds)
            && sinceLastFireMs >= Double(maxIntervalMilliseconds) / 2

        var leading: DispatchWorkItem?
        if isNewBurst {
            leadingWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.fireNotify(reason: .leading)
            }
            leadingWork = work
            leading = work
        }

        trailingWork?.cancel()
        let trailingDelay = needsForcedRefresh ? 0 : trailingMilliseconds
        let trailing = DispatchWorkItem { [weak self] in
            self?.fireNotify(reason: .trailing)
        }
        trailingWork = trailing
        stateLock.unlock()

        if let leading {
            queue.asyncAfter(
                deadline: .now() + .milliseconds(leadingMilliseconds),
                execute: leading
            )
        }
        queue.asyncAfter(
            deadline: .now() + .milliseconds(trailingDelay),
            execute: trailing
        )
    }

    private enum FireReason {
        case leading
        case trailing
    }

    private func fireNotify(reason: FireReason) {
        stateLock.lock()
        switch reason {
        case .leading:
            leadingWork = nil
        case .trailing:
            trailingWork = nil
            leadingWork?.cancel()
            leadingWork = nil
            burstStartedAt = nil
        }
        lastFiredAt = Date()
        stateLock.unlock()
        onChange?()
    }
}

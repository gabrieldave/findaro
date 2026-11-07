import AppKit
import UniformTypeIdentifiers

/// Resuelve `NSItemProvider` fileURL sin data races (caja + NSLock).
enum DropPathCollector {
    private final class PathBox: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []

        func append(_ path: String) {
            lock.lock()
            paths.append(path)
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return paths
        }
    }

    static func collect(
        _ providers: [NSItemProvider],
        typeIdentifier: String = UTType.fileURL.identifier,
        then: @escaping (_ paths: [String]) -> Void
    ) {
        let box = PathBox()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                defer { group.leave() }
                let path: String?
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    path = url.path
                } else if let url = item as? URL {
                    path = url.path
                } else {
                    path = nil
                }
                guard let path else { return }
                box.append(path)
            }
        }

        group.notify(queue: .main) {
            then(box.snapshot())
        }
    }
}

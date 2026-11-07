import AppKit
import UniformTypeIdentifiers

/// Resuelve providers de fileURL en callbacks concurrentes con NSLock (sin data race).
enum DualPaneDrop {
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

    static func handle(
        _ providers: [NSItemProvider],
        onPaths: @escaping (_ paths: [String], _ copy: Bool) -> Void
    ) -> Bool {
        let box = PathBox()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
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
            let copy = NSEvent.modifierFlags.contains(.option)
            onPaths(box.snapshot(), copy)
        }
        return true
    }
}

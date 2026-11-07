import AppKit
import UniformTypeIdentifiers

/// Resuelve providers de fileURL en callbacks concurrentes con NSLock (sin data race).
enum DualPaneDrop {
    static func handle(
        _ providers: [NSItemProvider],
        onPaths: @escaping (_ paths: [String], _ copy: Bool) -> Void
    ) -> Bool {
        let lock = NSLock()
        var paths: [String] = []
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
                lock.lock()
                paths.append(path)
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            lock.lock()
            let snapshot = paths
            lock.unlock()
            let copy = NSEvent.modifierFlags.contains(.option)
            onPaths(snapshot, copy)
        }
        return true
    }
}

import AppKit
import UniformTypeIdentifiers

/// Resuelve `NSItemProvider` fileURL sin data races (NSLock + DispatchGroup).
enum DropPathCollector {
    static func collect(
        _ providers: [NSItemProvider],
        typeIdentifier: String = UTType.fileURL.identifier,
        then: @escaping (_ paths: [String]) -> Void
    ) {
        let lock = NSLock()
        var paths: [String] = []
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
                lock.lock()
                paths.append(path)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            lock.lock()
            let snapshot = paths
            lock.unlock()
            then(snapshot)
        }
    }
}

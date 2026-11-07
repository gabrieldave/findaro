import AppKit
import UniformTypeIdentifiers

/// Resuelve providers de fileURL en el hilo principal (drop entre paneles / Finder).
enum DualPaneDrop {
    static func handle(
        _ providers: [NSItemProvider],
        onPaths: @escaping (_ paths: [String], _ copy: Bool) -> Void
    ) -> Bool {
        var paths: [String] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    paths.append(url.path)
                } else if let url = item as? URL {
                    paths.append(url.path)
                }
            }
        }
        group.notify(queue: .main) {
            let copy = NSEvent.modifierFlags.contains(.option)
            onPaths(paths, copy)
        }
        return true
    }
}

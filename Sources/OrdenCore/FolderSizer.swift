import Foundation

/// Medición de tamaños de archivos y carpetas.
public enum FolderSizer {
    public struct Measurement: Equatable, Sendable {
        public let bytes: Int64
        public let isComplete: Bool
        public let visitedItems: Int

        public init(bytes: Int64, isComplete: Bool, visitedItems: Int) {
            self.bytes = bytes
            self.isComplete = isComplete
            self.visitedItems = visitedItems
        }
    }

    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func measure(path: String, isDirectory: Bool, maxItems: Int = 250_000) -> Int64 {
        measureDetailed(path: path, isDirectory: isDirectory, maxItems: maxItems).bytes
    }

    public static func measureDetailed(path: String, isDirectory: Bool, maxItems: Int = 250_000) -> Measurement {
        if !isDirectory {
            do {
                let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true, let size = values.fileSize else {
                    return Measurement(bytes: 0, isComplete: false, visitedItems: 1)
                }
                return Measurement(bytes: Int64(size), isComplete: true, visitedItems: 1)
            } catch {
                return Measurement(bytes: 0, isComplete: false, visitedItems: 1)
            }
        }
        return measureDirectoryDetailed(at: path, maxItems: maxItems)
    }

    public static func recursiveDirectorySize(at path: String, maxItems: Int = 250_000) -> Int64 {
        measureDirectoryDetailed(at: path, maxItems: maxItems).bytes
    }

    public static func measureDirectoryDetailed(at path: String, maxItems: Int = 250_000) -> Measurement {
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let iterator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
                options: []
              ) else {
            return Measurement(bytes: 0, isComplete: false, visitedItems: 0)
        }

        let limit = max(1, maxItems)
        var total: Int64 = 0
        var count = 0
        var complete = true

        while let url = iterator.nextObject() as? URL {
            count += 1
            if count > limit {
                complete = false
                break
            }
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    complete = false
                    iterator.skipDescendants()
                    continue
                }
                if values.isRegularFile == true {
                    total += Int64(values.fileSize ?? 0)
                }
            } catch {
                complete = false
            }
        }

        return Measurement(bytes: total, isComplete: complete, visitedItems: count)
    }

    public static func sum(_ entries: [FileEntry]) -> Int64 {
        entries.reduce(0) { $0 + $1.size }
    }
}

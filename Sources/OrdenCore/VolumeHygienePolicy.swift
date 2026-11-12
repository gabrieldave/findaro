import Foundation

public struct VolumeHygieneTraits: Sendable, Equatable {
    public let isLocal: Bool
    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isReadOnly: Bool

    public var shouldAvoidAuxiliaryMetadata: Bool {
        !isLocal || isRemovable || isEjectable || isReadOnly
    }

    public init(
        isLocal: Bool,
        isRemovable: Bool,
        isEjectable: Bool,
        isReadOnly: Bool
    ) {
        self.isLocal = isLocal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isReadOnly = isReadOnly
    }
}

public struct VolumeHygienePolicy: Sendable {
    public static let macOSJunkFileNames: Set<String> = [
        ".DS_Store",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems"
    ]

    public init() {}

    public func inspectVolume(at url: URL) -> VolumeHygieneTraits {
        let keys: Set<URLResourceKey> = [
            .volumeIsLocalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsReadOnlyKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        return VolumeHygieneTraits(
            isLocal: values?.volumeIsLocal ?? true,
            isRemovable: values?.volumeIsRemovable ?? false,
            isEjectable: values?.volumeIsEjectable ?? false,
            isReadOnly: values?.volumeIsReadOnly ?? false
        )
    }

    public func isSystemClutterFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if Self.macOSJunkFileNames.contains(name) {
            return true
        }
        if name.hasPrefix("._") && name.count > 2 {
            return true
        }
        return false
    }

    @discardableResult
    public func purgeDSStoreAndAppleDouble(
        in directory: URL,
        recursive: Bool = false,
        fileManager: FileManager = .default
    ) -> Int {
        var removedCount = 0

        // Foundation's directory listings intentionally hide AppleDouble files
        // (`._*`), so a POSIX scan is required to see and delete them.
        for entry in Self.directoryEntries(at: directory) {
            let name = entry.url.lastPathComponent
            if name == ".DS_Store" || (name.hasPrefix("._") && name.count > 2) {
                if (try? fileManager.removeItem(at: entry.url)) != nil {
                    removedCount += 1
                }
                continue
            }

            if recursive, entry.isDirectory, !entry.isSymbolicLink, !entry.isPackage {
                removedCount += purgeDSStoreAndAppleDouble(
                    in: entry.url,
                    recursive: true,
                    fileManager: fileManager
                )
            }
        }

        return removedCount
    }

    private struct DirectoryEntry {
        let url: URL
        let isDirectory: Bool
        let isSymbolicLink: Bool
        let isPackage: Bool
    }

    private static func directoryEntries(at directory: URL) -> [DirectoryEntry] {
        guard let handle = opendir(directory.path) else { return [] }
        defer { closedir(handle) }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        var entries: [DirectoryEntry] = []

        while let rawEntry = readdir(handle) {
            let name = withUnsafePointer(to: rawEntry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }

            let entryURL = directory.appendingPathComponent(name, isDirectory: false)
            let values = try? entryURL.resourceValues(forKeys: keys)
            entries.append(
                DirectoryEntry(
                    url: entryURL,
                    isDirectory: values?.isDirectory ?? false,
                    isSymbolicLink: values?.isSymbolicLink ?? false,
                    isPackage: values?.isPackage ?? false
                )
            )
        }

        return entries
    }
}

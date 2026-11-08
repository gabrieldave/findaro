import Foundation
import UniformTypeIdentifiers

public enum DirectoryLoader {
    public static func load(path: String, includeHidden: Bool = false) throws -> [FileEntry] {
        let isTrash = TrashOps.isTrashPath(path)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !isTrash {
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                throw DirectoryError.notADirectory(path)
            }
        }

        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .addedToDirectoryDateKey,
            .localizedTypeDescriptionKey,
            .isHiddenKey
        ]

        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: includeHidden ? [] : [.skipsHiddenFiles]
            )

            return contents.compactMap { item in
                guard let values = try? item.resourceValues(forKeys: Set(keys)) else { return nil }
                if !includeHidden, values.isHidden == true { return nil }

                let isDirectory = values.isDirectory ?? false
                let size = Int64(values.fileSize ?? 0)
                let modified = values.contentModificationDate ?? .distantPast
                let created = values.creationDate ?? .distantPast
                let added = values.addedToDirectoryDate ?? created
                let kind = values.localizedTypeDescription
                    ?? UTType(filenameExtension: item.pathExtension)?.localizedDescription
                    ?? (isDirectory ? "Carpeta" : "Documento")

                return FileEntry(
                    path: item.path,
                    name: item.lastPathComponent,
                    isDirectory: isDirectory,
                    size: size,
                    dateModified: modified,
                    dateCreated: created,
                    dateAdded: added,
                    kind: kind
                )
            }
        } catch {
            if isTrash {
                let finderEntries = TrashOps.loadTrashViaFinder()
                return finderEntries
            }
            throw error
        }
    }
}

public enum DirectoryError: Error, LocalizedError {
    case notADirectory(String)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let path):
            return "No es una carpeta: \(path)"
        }
    }
}

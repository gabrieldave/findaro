import Foundation

/// Vista plana: archivos (y carpetas opcionales) bajo una raíz, sin seguir
/// symlinks fuera del árbol. Límite de profundidad para no congelar el UI.
public enum DirectoryFlatten {
    public static func load(
        root: String,
        includeHidden: Bool = false,
        includeDirectories: Bool = false,
        maxDepth: Int = 8,
        maxItems: Int = 4_000
    ) throws -> [FileEntry] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw DirectoryError.notADirectory(root)
        }

        var results: [FileEntry] = []
        var stack: [(url: URL, depth: Int)] = [(rootURL, 0)]
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .addedToDirectoryDateKey, .localizedTypeDescriptionKey,
            .isHiddenKey, .isSymbolicLinkKey
        ]

        while let current = stack.popLast() {
            if results.count >= maxItems { break }
            if current.depth > maxDepth { continue }

            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(
                    at: current.url,
                    includingPropertiesForKeys: Array(keys),
                    options: includeHidden ? [] : [.skipsHiddenFiles]
                )
            } catch {
                continue
            }

            for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                if results.count >= maxItems { break }
                guard let values = try? child.resourceValues(forKeys: keys) else { continue }
                if !includeHidden, values.isHidden == true { continue }
                if values.isSymbolicLink == true {
                    let resolved = child.resolvingSymlinksInPath()
                    let rootPath = rootURL.path
                    let resolvedPath = resolved.path
                    guard resolvedPath == rootPath
                        || resolvedPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
                        continue
                    }
                }

                let isDirectory = values.isDirectory ?? false
                if isDirectory {
                    if includeDirectories, current.depth > 0 {
                        results.append(makeEntry(child, values: values, isDirectory: true))
                    }
                    if current.depth < maxDepth {
                        stack.append((child, current.depth + 1))
                    }
                } else {
                    results.append(makeEntry(child, values: values, isDirectory: false))
                }
            }
        }

        return results
    }

    private static func makeEntry(
        _ url: URL,
        values: URLResourceValues,
        isDirectory: Bool
    ) -> FileEntry {
        let size = Int64(values.fileSize ?? 0)
        let modified = values.contentModificationDate ?? .distantPast
        let created = values.creationDate ?? .distantPast
        let added = values.addedToDirectoryDate ?? created
        let kind = values.localizedTypeDescription
            ?? (isDirectory ? "Carpeta" : "Documento")
        return FileEntry(
            path: url.path,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            size: size,
            dateModified: modified,
            dateCreated: created,
            dateAdded: added,
            kind: kind
        )
    }
}

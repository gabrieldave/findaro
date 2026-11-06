import Foundation

public struct SearchHit: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let modified: Date?

    public init(path: String, name: String, isDirectory: Bool, size: Int64, modified: Date?) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
    }
}

public struct SearchProgress: Equatable, Sendable {
    public var visitedFolders: Int
    public var matched: Int
    public var currentFolder: String
    public var done: Bool

    public init(visitedFolders: Int = 0, matched: Int = 0, currentFolder: String = "", done: Bool = false) {
        self.visitedFolders = visitedFolders
        self.matched = matched
        self.currentFolder = currentFolder
        self.done = done
    }
}

public enum RecursiveSearch {
    public struct Query: Equatable, Sendable {
        public var text: String
        public var root: String
        public var maxResults: Int
        public var maxDepth: Int

        public init(text: String, root: String, maxResults: Int = 400, maxDepth: Int = 12) {
            self.text = text
            self.root = root
            self.maxResults = maxResults
            self.maxDepth = maxDepth
        }
    }

    /// Enumera el árbol buscando en nombre (case-insensitive). Reporta progreso.
    public static func run(
        query: Query,
        isCancelled: @escaping () -> Bool,
        onProgress: @escaping (SearchProgress) -> Void,
        onHit: @escaping (SearchHit) -> Void
    ) {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            onProgress(SearchProgress(done: true))
            return
        }

        let fm = FileManager.default
        var visited = 0
        var matched = 0
        var stack: [(path: String, depth: Int)] = [(query.root, 0)]

        while let next = stack.popLast() {
            if isCancelled() { break }
            visited += 1
            onProgress(SearchProgress(
                visitedFolders: visited,
                matched: matched,
                currentFolder: next.path,
                done: false
            ))

            guard let items = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: next.path),
                includingPropertiesForKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey
                ],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for url in items {
                if isCancelled() { break }
                let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey
                ])
                if values?.isHidden == true { continue }
                let name = url.lastPathComponent
                let isDir = values?.isDirectory == true
                if name.lowercased().contains(needle) {
                    matched += 1
                    onHit(SearchHit(
                        path: url.path,
                        name: name,
                        isDirectory: isDir,
                        size: Int64(values?.fileSize ?? 0),
                        modified: values?.contentModificationDate
                    ))
                    if matched >= query.maxResults {
                        onProgress(SearchProgress(
                            visitedFolders: visited,
                            matched: matched,
                            currentFolder: next.path,
                            done: true
                        ))
                        return
                    }
                }
                if isDir, next.depth < query.maxDepth {
                    // Evitar bucles por symlinks pesados: solo rutas reales bajo root.
                    let standardized = (url.path as NSString).standardizingPath
                    if standardized.hasPrefix((query.root as NSString).standardizingPath) {
                        stack.append((standardized, next.depth + 1))
                    }
                }
            }
        }

        onProgress(SearchProgress(
            visitedFolders: visited,
            matched: matched,
            currentFolder: query.root,
            done: true
        ))
    }
}

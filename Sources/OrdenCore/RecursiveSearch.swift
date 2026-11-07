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
        public var searchContent: Bool
        public var maxContentBytes: Int

        public init(
            text: String,
            root: String,
            maxResults: Int = 400,
            maxDepth: Int = 12,
            searchContent: Bool = false,
            maxContentBytes: Int = 2_000_000
        ) {
            self.text = text
            self.root = root
            self.maxResults = maxResults
            self.maxDepth = maxDepth
            self.searchContent = searchContent
            self.maxContentBytes = maxContentBytes
        }
    }

    public static let textContentExtensions: Set<String> = [
        "txt", "md", "markdown", "text", "log", "csv", "tsv", "json", "yml", "yaml", "toml", "xml",
        "html", "htm", "css", "scss", "js", "jsx", "ts", "tsx", "swift", "py", "rs", "go", "java",
        "kt", "c", "h", "cpp", "hpp", "m", "mm", "rb", "php", "sh", "zsh", "bash", "sql", "rtf"
    ]

    /// Busca en la carpeta actual y sus descendientes reales. No sigue enlaces simbólicos
    /// que apunten fuera del árbol solicitado.
    public static func run(
        query: Query,
        isCancelled: @escaping () -> Bool,
        onProgress: @escaping (SearchProgress) -> Void,
        onHit: @escaping (SearchHit) -> Void
    ) {
        let rawNeedle = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = rawNeedle
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else {
            onProgress(SearchProgress(done: true))
            return
        }

        let root = URL(fileURLWithPath: query.root).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let maxResults = max(1, query.maxResults)
        let maxDepth = max(0, query.maxDepth)
        let fm = FileManager.default
        var visited = 0
        var matched = 0
        var stack: [(path: String, depth: Int)] = [(rootPath, 0)]

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
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .isSymbolicLinkKey
                ],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for url in items {
                if isCancelled() { break }
                guard let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .isSymbolicLinkKey
                ]) else { continue }

                if values.isHidden == true || values.isSymbolicLink == true { continue }

                let itemPath = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard isSameOrDescendant(itemPath, of: rootPath) else { continue }

                let name = url.lastPathComponent
                let isDirectory = values.isDirectory == true
                let size = Int64(values.fileSize ?? 0)
                let nameHit = name.lowercased().contains(needle)
                let contentHit: Bool = {
                    guard query.searchContent, !isDirectory, !nameHit else { return false }
                    return fileContains(url, needle: needle, maxBytes: query.maxContentBytes)
                }()

                if nameHit || contentHit {
                    matched += 1
                    onHit(SearchHit(
                        path: url.path,
                        name: name,
                        isDirectory: isDirectory,
                        size: size,
                        modified: values.contentModificationDate
                    ))
                    if matched >= maxResults {
                        onProgress(SearchProgress(
                            visitedFolders: visited,
                            matched: matched,
                            currentFolder: next.path,
                            done: true
                        ))
                        return
                    }
                }

                if isDirectory, next.depth < maxDepth {
                    stack.append((itemPath, next.depth + 1))
                }
            }
        }

        onProgress(SearchProgress(
            visitedFolders: visited,
            matched: matched,
            currentFolder: rootPath,
            done: true
        ))
    }

    public static func isTextContentFile(name: String) -> Bool {
        textContentExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        if path == root { return true }
        let prefix = root == "/" ? "/" : root + "/"
        return path.hasPrefix(prefix)
    }

    private static func fileContains(_ url: URL, needle: String, maxBytes: Int) -> Bool {
        guard isTextContentFile(name: url.lastPathComponent), maxBytes > 0,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let data: Data
        do {
            data = try handle.read(upToCount: maxBytes) ?? Data()
        } catch {
            return false
        }
        if data.contains(0) { return false }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return false }
        return text.lowercased().contains(needle)
    }
}

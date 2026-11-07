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
        /// Si true, también mira dentro de archivos de texto/código (límite de tamaño).
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

    /// Extensiones donde tiene sentido buscar texto plano.
    public static let textContentExtensions: Set<String> = [
        "txt", "md", "markdown", "text", "log", "csv", "tsv", "json", "yml", "yaml", "toml", "xml",
        "html", "htm", "css", "scss", "js", "jsx", "ts", "tsx", "swift", "py", "rs", "go", "java",
        "kt", "c", "h", "cpp", "hpp", "m", "mm", "rb", "php", "sh", "zsh", "bash", "sql", "rtf"
    ]

    /// Enumera el árbol buscando en nombre (y opcionalmente contenido). Reporta progreso.
    public static func run(
        query: Query,
        isCancelled: @escaping () -> Bool,
        onProgress: @escaping (SearchProgress) -> Void,
        onHit: @escaping (SearchHit) -> Void
    ) {
        // Comodines tipo Finder: `*.png` → buscar `.png` (no es glob real).
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
                let size = Int64(values?.fileSize ?? 0)
                let nameHit = name.lowercased().contains(needle)
                let contentHit: Bool = {
                    guard query.searchContent, !isDir, !nameHit else { return false }
                    return fileContains(url, needle: needle, maxBytes: query.maxContentBytes)
                }()
                if nameHit || contentHit {
                    matched += 1
                    onHit(SearchHit(
                        path: url.path,
                        name: name,
                        isDirectory: isDir,
                        size: size,
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

    public static func isTextContentFile(name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return textContentExtensions.contains(ext)
    }

    private static func fileContains(_ url: URL, needle: String, maxBytes: Int) -> Bool {
        guard isTextContentFile(name: url.lastPathComponent) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let data: Data
        do {
            if #available(macOS 10.15.4, *) {
                guard let chunk = try handle.read(upToCount: maxBytes) else { return false }
                data = chunk
            } else {
                data = handle.readData(ofLength: maxBytes)
            }
        } catch {
            return false
        }
        if data.contains(0) { return false }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return false }
        return text.lowercased().contains(needle)
    }
}

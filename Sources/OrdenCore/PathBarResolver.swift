import Foundation

public enum PathResolutionResult: Sendable, Equatable {
    case directory(URL)
    case fileParent(directory: URL, targetFile: URL)
    case notFound(expandedPath: String)
}

public struct PathBarResolver: Sendable {
    public init() {}

    public func resolve(input: String, fileManager: FileManager = .default) -> PathResolutionResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .notFound(expandedPath: "")
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return .notFound(expandedPath: url.path)
        }

        if isDir.boolValue {
            return .directory(url)
        } else {
            return .fileParent(directory: url.deletingLastPathComponent(), targetFile: url)
        }
    }

    public func autocompleteDirectories(
        for rawInput: String,
        limit: Int = 12,
        fileManager: FileManager = .default
    ) -> [URL] {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let rawHadTrailingSlash = trimmed.hasSuffix("/") && trimmed.count > 1
        let expandedBase = (trimmed as NSString).expandingTildeInPath
        let expanded = (rawHadTrailingSlash && !expandedBase.hasSuffix("/")) ? (expandedBase + "/") : expandedBase
        let endsWithSlash = expanded.hasSuffix("/") && expanded.count > 1

        let searchDirectoryURL: URL
        let prefix: String

        if expanded == "/" {
            searchDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
            prefix = ""
        } else if endsWithSlash {
            searchDirectoryURL = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            prefix = ""
        } else {
            let candidateURL = URL(fileURLWithPath: expanded)
            searchDirectoryURL = candidateURL.deletingLastPathComponent().standardizedFileURL
            prefix = candidateURL.lastPathComponent
        }

        let showHidden = prefix.hasPrefix(".")
        guard let contents = try? fileManager.contentsOfDirectory(
            at: searchDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let matches = contents.filter { itemURL in
            let name = itemURL.lastPathComponent
            if name == ".DS_Store" { return false }
            if !showHidden && name.hasPrefix(".") { return false }

            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            guard values?.isDirectory == true else { return false }
            if !showHidden && (values?.isHidden == true) { return false }

            if prefix.isEmpty { return true }
            return name.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
        }

        let sorted = matches.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        return Array(sorted.prefix(max(1, limit)))
    }
}

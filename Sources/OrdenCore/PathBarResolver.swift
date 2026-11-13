import Foundation

import Foundation

public struct BreadcrumbSegment: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let title: String
    public let path: String
    public let isHome: Bool
    public let isExternalVolume: Bool
    public let iconName: String?

    public init(
        title: String,
        path: String,
        isHome: Bool = false,
        isExternalVolume: Bool = false,
        iconName: String? = nil
    ) {
        self.title = title
        self.path = path
        self.isHome = isHome
        self.isExternalVolume = isExternalVolume
        self.iconName = iconName
    }
}

public struct BreadcrumbResolver: Sendable {
    public init() {}

    public static func segments(
        for url: URL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [BreadcrumbSegment] {
        segments(for: url.standardizedFileURL.path, homePath: homeURL.standardizedFileURL.path)
    }

    public static func segments(
        for rawPath: String,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    ) -> [BreadcrumbSegment] {
        let path = (rawPath as NSString).standardizingPath
        guard !path.isEmpty else { return [] }

        let normalizedHome = (homePath as NSString).standardizingPath

        // 1. Caso: Dentro de la carpeta personal (~)
        if path == normalizedHome {
            return [
                BreadcrumbSegment(
                    title: "~",
                    path: normalizedHome,
                    isHome: true,
                    isExternalVolume: false,
                    iconName: "house.fill"
                )
            ]
        } else if path.hasPrefix(normalizedHome + "/") {
            var segments: [BreadcrumbSegment] = [
                BreadcrumbSegment(
                    title: "~",
                    path: normalizedHome,
                    isHome: true,
                    isExternalVolume: false,
                    iconName: "house.fill"
                )
            ]
            let relative = String(path.dropFirst(normalizedHome.count + 1))
            var accumulated = normalizedHome
            for component in relative.split(separator: "/") {
                accumulated += "/" + component
                segments.append(
                    BreadcrumbSegment(
                        title: String(component),
                        path: accumulated,
                        isHome: false,
                        isExternalVolume: false,
                        iconName: nil
                    )
                )
            }
            return segments
        }

        // 2. Caso: Unidad externa o recurso de red (/Volumes/...)
        if path.hasPrefix("/Volumes/") && path != "/Volumes" {
            let relative = String(path.dropFirst("/Volumes/".count))
            let parts = relative.split(separator: "/")
            if let volumeName = parts.first {
                var accumulated = "/Volumes/" + volumeName
                var segments: [BreadcrumbSegment] = [
                    BreadcrumbSegment(
                        title: String(volumeName),
                        path: accumulated,
                        isHome: false,
                        isExternalVolume: true,
                        iconName: "externaldrive.fill"
                    )
                ]
                for component in parts.dropFirst() {
                    accumulated += "/" + component
                    segments.append(
                        BreadcrumbSegment(
                            title: String(component),
                            path: accumulated,
                            isHome: false,
                            isExternalVolume: false,
                            iconName: nil
                        )
                    )
                }
                return segments
            }
        }

        // 3. Caso: Raíz del sistema u otras rutas absolutas
        var segments: [BreadcrumbSegment] = [
            BreadcrumbSegment(
                title: "/",
                path: "/",
                isHome: false,
                isExternalVolume: false,
                iconName: "internaldrive"
            )
        ]
        if path == "/" {
            return segments
        }

        var accumulated = ""
        for component in path.split(separator: "/") {
            accumulated += "/" + component
            segments.append(
                BreadcrumbSegment(
                    title: String(component),
                    path: accumulated,
                    isHome: false,
                    isExternalVolume: false,
                    iconName: nil
                )
            )
        }
        return segments
    }
}

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

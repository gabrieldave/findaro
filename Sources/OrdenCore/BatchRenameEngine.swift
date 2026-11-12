import Foundation

public enum BatchRenameCaseStyle: String, Sendable, Equatable, CaseIterable {
    case lowercase
    case uppercase
    case titleCase
}

public enum BatchRenameRule: Sendable, Equatable {
    case replaceText(find: String, replace: String, caseSensitive: Bool)
    case regexReplace(pattern: String, template: String)
    case addAffix(prefix: String, suffix: String)
    case changeCase(BatchRenameCaseStyle)
    case sequential(baseName: String, startAt: Int, paddingDigits: Int, separator: String)
}

public enum BatchRenameConflict: String, Sendable, Equatable {
    case emptyName
    case invalidCharacters
    case duplicateInBatch
    case alreadyExistsOnDisk
    case invalidRegex
}

public struct BatchRenamePreviewItem: Sendable, Equatable, Identifiable {
    public var id: URL { sourceURL }
    public let sourceURL: URL
    public let originalName: String
    public let proposedName: String
    public let destinationURL: URL
    public let conflict: BatchRenameConflict?

    public var hasChanges: Bool {
        originalName != proposedName
    }

    public var canApply: Bool {
        hasChanges && conflict == nil
    }

    public init(
        sourceURL: URL,
        originalName: String,
        proposedName: String,
        destinationURL: URL,
        conflict: BatchRenameConflict?
    ) {
        self.sourceURL = sourceURL
        self.originalName = originalName
        self.proposedName = proposedName
        self.destinationURL = destinationURL
        self.conflict = conflict
    }
}

public struct BatchRenameEngine: Sendable {
    public init() {}

    public func preview(
        urls: [URL],
        rules: [BatchRenameRule],
        fileManager: FileManager = .default
    ) -> [BatchRenamePreviewItem] {
        guard !urls.isEmpty else { return [] }

        var compiledRegexConflict = false
        for rule in rules {
            if case let .regexReplace(pattern, _) = rule, !pattern.isEmpty {
                if (try? NSRegularExpression(pattern: pattern)) == nil {
                    compiledRegexConflict = true
                }
            }
        }

        let sourcePathSet = Set(urls.map { $0.standardizedFileURL.path.lowercased() })
        var draftResults: [(source: URL, original: String, proposed: String, dest: URL, initialConflict: BatchRenameConflict?)] = []
        draftResults.reserveCapacity(urls.count)

        for (index, url) in urls.enumerated() {
            let standardized = url.standardizedFileURL
            let originalName = standardized.lastPathComponent
            let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? standardized.hasDirectoryPath

            if compiledRegexConflict {
                draftResults.append((standardized, originalName, originalName, standardized, .invalidRegex))
                continue
            }

            let (stem, ext) = splitNameAndExtension(originalName, isDirectory: isDirectory)
            var currentStem = stem

            for rule in rules {
                currentStem = apply(rule: rule, to: currentStem, index: index)
            }

            let trimmedStem = currentStem.trimmingCharacters(in: .whitespacesAndNewlines)
            let proposedName: String
            if trimmedStem.isEmpty {
                proposedName = ""
            } else if ext.isEmpty {
                proposedName = trimmedStem
            } else {
                proposedName = "\(trimmedStem).\(ext)"
            }

            let parentDir = standardized.deletingLastPathComponent()
            let destURL = proposedName.isEmpty ? standardized : parentDir.appendingPathComponent(proposedName, isDirectory: isDirectory)

            var conflict: BatchRenameConflict? = nil
            if proposedName.isEmpty || proposedName == "." || proposedName == ".." {
                conflict = .emptyName
            } else if proposedName.contains("/") || proposedName.contains(":") || proposedName.contains("\0") {
                conflict = .invalidCharacters
            } else if proposedName != originalName {
                let destLower = destURL.standardizedFileURL.path.lowercased()
                let isSameFileCaseChange = (destLower == standardized.path.lowercased())
                if !isSameFileCaseChange && !sourcePathSet.contains(destLower) && fileManager.fileExists(atPath: destURL.path) {
                    conflict = .alreadyExistsOnDisk
                }
            }

            draftResults.append((standardized, originalName, proposedName, destURL, conflict))
        }

        var seenDestinations: [String: Int] = [:]
        for item in draftResults where !item.proposed.isEmpty {
            let key = item.dest.standardizedFileURL.path.lowercased()
            seenDestinations[key, default: 0] += 1
        }

        return draftResults.map { item in
            var finalConflict = item.initialConflict
            if finalConflict == nil, !item.proposed.isEmpty {
                let key = item.dest.standardizedFileURL.path.lowercased()
                if (seenDestinations[key] ?? 0) > 1 {
                    finalConflict = .duplicateInBatch
                }
            }
            return BatchRenamePreviewItem(
                sourceURL: item.source,
                originalName: item.original,
                proposedName: item.proposed,
                destinationURL: item.dest,
                conflict: finalConflict
            )
        }
    }

    public func splitNameAndExtension(_ name: String, isDirectory: Bool) -> (stem: String, ext: String) {
        if isDirectory {
            return (name, "")
        }
        if name.hasPrefix(".") && !name.dropFirst().contains(".") {
            return (name, "")
        }
        let nsName = name as NSString
        let ext = nsName.pathExtension
        let stem = nsName.deletingPathExtension
        if stem.isEmpty {
            return (name, "")
        }
        return (stem, ext)
    }

    private func apply(rule: BatchRenameRule, to stem: String, index: Int) -> String {
        switch rule {
        case let .replaceText(find, replace, caseSensitive):
            guard !find.isEmpty else { return stem }
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            return stem.replacingOccurrences(of: find, with: replace, options: options)

        case let .regexReplace(pattern, template):
            guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else { return stem }
            let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
            return regex.stringByReplacingMatches(in: stem, options: [], range: range, withTemplate: template)

        case let .addAffix(prefix, suffix):
            return "\(prefix)\(stem)\(suffix)"

        case let .changeCase(style):
            switch style {
            case .lowercase:
                return stem.lowercased()
            case .uppercase:
                return stem.uppercased()
            case .titleCase:
                return stem.localizedCapitalized
            }

        case let .sequential(baseName, startAt, paddingDigits, separator):
            let number = startAt + index
            let format = "%0\(max(1, paddingDigits))d"
            let padded = String(format: format, number)
            let cleanBase = baseName.isEmpty ? stem : baseName
            return "\(cleanBase)\(separator)\(padded)"
        }
    }
}

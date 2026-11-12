import Foundation

public struct BatchRenameAppliedPair: Sendable, Equatable {
    public let originalURL: URL
    public let renamedURL: URL

    public init(originalURL: URL, renamedURL: URL) {
        self.originalURL = originalURL
        self.renamedURL = renamedURL
    }
}

public struct BatchRenameTransaction: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let appliedPairs: [BatchRenameAppliedPair]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        appliedPairs: [BatchRenameAppliedPair]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appliedPairs = appliedPairs
    }
}

public enum BatchRenameExecutionError: Error, Sendable, Equatable {
    case noEffectiveChanges
    case conflictsDetected([BatchRenameConflict])
    case executionFailedAndRolledBack(failedItem: String, underlyingMessage: String)
    case rollbackIncomplete(failedItem: String, unrecoveredItems: [String])
}

public struct BatchRenameExecutor: Sendable {
    public init() {}

    public func execute(
        previewItems: [BatchRenamePreviewItem],
        fileManager: FileManager = .default
    ) throws -> BatchRenameTransaction {
        let conflicts = previewItems.compactMap(\.conflict)
        if !conflicts.isEmpty {
            throw BatchRenameExecutionError.conflictsDetected(conflicts)
        }

        let actionable = previewItems.filter(\.hasChanges)
        guard !actionable.isEmpty else {
            throw BatchRenameExecutionError.noEffectiveChanges
        }

        let pairs = actionable.map {
            (from: $0.sourceURL.standardizedFileURL, to: $0.destinationURL.standardizedFileURL)
        }

        try performTwoPhaseMove(pairs: pairs, fileManager: fileManager)

        let applied = pairs.map {
            BatchRenameAppliedPair(originalURL: $0.from, renamedURL: $0.to)
        }
        return BatchRenameTransaction(appliedPairs: applied)
    }

    @discardableResult
    public func undo(
        _ transaction: BatchRenameTransaction,
        fileManager: FileManager = .default
    ) throws -> BatchRenameTransaction {
        guard !transaction.appliedPairs.isEmpty else {
            throw BatchRenameExecutionError.noEffectiveChanges
        }

        let reversePairs = transaction.appliedPairs.reversed().map {
            (from: $0.renamedURL.standardizedFileURL, to: $0.originalURL.standardizedFileURL)
        }

        try performTwoPhaseMove(pairs: reversePairs, fileManager: fileManager)

        let reverted = reversePairs.map {
            BatchRenameAppliedPair(originalURL: $0.from, renamedURL: $0.to)
        }
        return BatchRenameTransaction(appliedPairs: reverted)
    }

    private func performTwoPhaseMove(
        pairs: [(from: URL, to: URL)],
        fileManager: FileManager
    ) throws {
        let batchToken = UUID().uuidString.lowercased()
        let stagedPlan: [(from: URL, staging: URL, to: URL)] = pairs.enumerated().map { index, pair in
            let parent = pair.from.deletingLastPathComponent()
            let tempName = ".findaro_staging_\(batchToken)_\(index)"
            let stagingURL = parent.appendingPathComponent(tempName, isDirectory: pair.from.hasDirectoryPath)
            return (from: pair.from, staging: stagingURL, to: pair.to)
        }

        var movedToStagingCount = 0
        do {
            for entry in stagedPlan {
                try fileManager.moveItem(at: entry.from, to: entry.staging)
                movedToStagingCount += 1
            }
        } catch {
            let failedName = stagedPlan[movedToStagingCount].from.lastPathComponent
            var unrecovered: [String] = []
            for idx in stride(from: movedToStagingCount - 1, through: 0, by: -1) {
                let entry = stagedPlan[idx]
                do {
                    try fileManager.moveItem(at: entry.staging, to: entry.from)
                } catch {
                    unrecovered.append(entry.from.lastPathComponent)
                }
            }
            if !unrecovered.isEmpty {
                throw BatchRenameExecutionError.rollbackIncomplete(
                    failedItem: failedName,
                    unrecoveredItems: unrecovered
                )
            }
            throw BatchRenameExecutionError.executionFailedAndRolledBack(
                failedItem: failedName,
                underlyingMessage: error.localizedDescription
            )
        }

        var movedToFinalCount = 0
        do {
            for entry in stagedPlan {
                try fileManager.moveItem(at: entry.staging, to: entry.to)
                movedToFinalCount += 1
            }
        } catch {
            let failedName = stagedPlan[movedToFinalCount].to.lastPathComponent
            var unrecovered: [String] = []

            for idx in stride(from: movedToFinalCount - 1, through: 0, by: -1) {
                let entry = stagedPlan[idx]
                do {
                    try fileManager.moveItem(at: entry.to, to: entry.staging)
                } catch {
                    unrecovered.append(entry.from.lastPathComponent)
                }
            }

            for idx in stride(from: stagedPlan.count - 1, through: 0, by: -1) {
                let entry = stagedPlan[idx]
                if fileManager.fileExists(atPath: entry.staging.path) {
                    do {
                        try fileManager.moveItem(at: entry.staging, to: entry.from)
                    } catch {
                        unrecovered.append(entry.from.lastPathComponent)
                    }
                }
            }

            if !unrecovered.isEmpty {
                throw BatchRenameExecutionError.rollbackIncomplete(
                    failedItem: failedName,
                    unrecoveredItems: Array(Set(unrecovered)).sorted()
                )
            }
            throw BatchRenameExecutionError.executionFailedAndRolledBack(
                failedItem: failedName,
                underlyingMessage: error.localizedDescription
            )
        }
    }
}

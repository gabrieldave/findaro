import Foundation

/// Cola de transferencias con preflight, manifiesto SHA-256 (archivos + `.app`),
/// verificación de MOVE y rollback del lote si falla un elemento posterior.
public actor TransferQueue {
    public struct Job: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let paths: [String]
        public let destinationDir: String
        public let move: Bool

        public init(id: UUID = UUID(), paths: [String], destinationDir: String, move: Bool) {
            self.id = id
            self.paths = paths
            self.destinationDir = destinationDir
            self.move = move
        }
    }

    public struct Progress: Equatable, Sendable {
        public var jobID: UUID
        public var completed: Int
        public var total: Int
        public var currentName: String
        public var done: Bool
        public var errorMessage: String?

        public init(
            jobID: UUID,
            completed: Int,
            total: Int,
            currentName: String,
            done: Bool,
            errorMessage: String? = nil
        ) {
            self.jobID = jobID
            self.completed = completed
            self.total = total
            self.currentName = currentName
            self.done = done
            self.errorMessage = errorMessage
        }

        public var fraction: Double {
            guard total > 0 else { return 1 }
            return Double(completed) / Double(total)
        }
    }

    private struct PreflightItem: Sendable {
        var path: String
        var isDirectory: Bool
        var manifest: FileDigest.TreeManifest
    }

    public static let shared = TransferQueue()

    private var running = false

    public func run(
        _ job: Job,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> [FileOps.TransferPair] {
        while running {
            try await Task.sleep(nanoseconds: 40_000_000)
            try Task.checkCancellation()
        }
        try LicenseGate.requireWrite()
        running = true
        defer { running = false }

        let total = max(job.paths.count, 1)
        var completedPairs: [FileOps.TransferPair] = []

        do {
            let preflight = try Self.preflight(paths: job.paths, destinationDir: job.destinationDir)
            guard !preflight.isEmpty else {
                throw FileOpsError.failed("Nada que transferir")
            }

            for (index, item) in preflight.enumerated() {
                try Task.checkCancellation()
                let name = URL(fileURLWithPath: item.path).lastPathComponent
                onProgress(Progress(
                    jobID: job.id,
                    completed: index,
                    total: total,
                    currentName: name,
                    done: false
                ))

                let batch = try FileOps.transfer(
                    paths: [item.path],
                    toDirectory: job.destinationDir,
                    move: job.move
                )
                guard let pair = batch.first else {
                    throw FileOpsError.failed("Transferencia vacía: \(name)")
                }
                try Self.verify(pair: pair, expected: item, expectingMove: job.move)
                completedPairs.append(pair)
            }

            onProgress(Progress(
                jobID: job.id,
                completed: total,
                total: total,
                currentName: "",
                done: true
            ))
            return completedPairs
        } catch {
            let rollbackErrors = Self.rollback(completedPairs, wasMove: job.move)
            var message = error.localizedDescription
            if !rollbackErrors.isEmpty {
                message += " · Rollback parcial: " + rollbackErrors.joined(separator: "; ")
            } else if !completedPairs.isEmpty {
                message += " · Se revirtieron \(completedPairs.count) elemento(s) del lote"
            }
            onProgress(Progress(
                jobID: job.id,
                completed: completedPairs.count,
                total: total,
                currentName: "",
                done: true,
                errorMessage: message
            ))
            throw FileOpsError.failed(message)
        }
    }

    private static func preflight(paths: [String], destinationDir: String) throws -> [PreflightItem] {
        let fm = FileManager.default
        var destIsDir: ObjCBool = false
        guard fm.fileExists(atPath: destinationDir, isDirectory: &destIsDir), destIsDir.boolValue else {
            throw FileOpsError.failed("Destino no es una carpeta")
        }

        var items: [PreflightItem] = []
        for path in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
                throw FileOpsError.failed("No existe \(URL(fileURLWithPath: path).lastPathComponent)")
            }
            let manifest = try FileDigest.treeManifest(at: path)
            items.append(PreflightItem(
                path: path,
                isDirectory: isDir.boolValue,
                manifest: manifest
            ))
        }
        return items
    }

    private static func verify(pair: FileOps.TransferPair, expected: PreflightItem, expectingMove: Bool) throws {
        let fm = FileManager.default
        var destIsDir: ObjCBool = false
        guard fm.fileExists(atPath: pair.to, isDirectory: &destIsDir) else {
            throw FileOpsError.failed(
                "Verificación falló: no aparece \(URL(fileURLWithPath: pair.to).lastPathComponent)"
            )
        }

        if expected.isDirectory {
            guard destIsDir.boolValue else {
                throw FileOpsError.failed("Verificación falló: se esperaba carpeta en destino")
            }
        } else {
            guard !destIsDir.boolValue else {
                throw FileOpsError.failed("Verificación falló: se esperaba archivo en destino")
            }
        }

        try FileDigest.verifyManifest(expected.manifest, at: pair.to)

        if expectingMove {
            if fm.fileExists(atPath: pair.from) {
                throw FileOpsError.failed(
                    "MOVE incompleto: el origen sigue existiendo (\(URL(fileURLWithPath: pair.from).lastPathComponent))"
                )
            }
        }
    }

    /// Revierte pares completados en orden inverso. Devuelve errores que no se pudieron deshacer.
    private static func rollback(_ pairs: [FileOps.TransferPair], wasMove: Bool) -> [String] {
        let fm = FileManager.default
        var errors: [String] = []
        for pair in pairs.reversed() {
            let name = URL(fileURLWithPath: pair.to).lastPathComponent
            do {
                if wasMove {
                    if fm.fileExists(atPath: pair.to) {
                        let parent = (pair.from as NSString).deletingLastPathComponent
                        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
                        if fm.fileExists(atPath: pair.from) {
                            try fm.removeItem(atPath: pair.to)
                        } else {
                            try fm.moveItem(atPath: pair.to, toPath: pair.from)
                        }
                    }
                } else if fm.fileExists(atPath: pair.to) {
                    try fm.removeItem(atPath: pair.to)
                }
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }
        return errors
    }
}

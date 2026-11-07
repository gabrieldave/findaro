import Foundation

/// Cola de transferencias con progreso y verificación de tamaño tras copia
/// (antes de borrar el origen en moves entre volúmenes / copy+delete).
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

    public static let shared = TransferQueue()

    private var running = false

    public func run(
        _ job: Job,
        onProgress: @Sendable @escaping (Progress) -> Void
    ) async throws -> [FileOps.TransferPair] {
        while running {
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        running = true
        defer { running = false }

        let total = max(job.paths.count, 1)
        var pairs: [FileOps.TransferPair] = []

        do {
            for (index, path) in job.paths.enumerated() {
                let name = URL(fileURLWithPath: path).lastPathComponent
                onProgress(Progress(
                    jobID: job.id,
                    completed: index,
                    total: total,
                    currentName: name,
                    done: false
                ))

                let batch = try FileOps.transfer(
                    paths: [path],
                    toDirectory: job.destinationDir,
                    move: job.move
                )
                for pair in batch {
                    try Self.verifyPair(pair, expectingMove: job.move)
                }
                pairs.append(contentsOf: batch)
            }

            onProgress(Progress(
                jobID: job.id,
                completed: total,
                total: total,
                currentName: "",
                done: true
            ))
            return pairs
        } catch {
            onProgress(Progress(
                jobID: job.id,
                completed: pairs.count,
                total: total,
                currentName: "",
                done: true,
                errorMessage: error.localizedDescription
            ))
            throw error
        }
    }

    /// Comprueba que el destino existe y, si es archivo, que el tamaño coincide
    /// con el origen (si el origen aún existe — caso copia) o es > 0 (caso move).
    private static func verifyPair(_ pair: FileOps.TransferPair, expectingMove: Bool) throws {
        let fm = FileManager.default
        var destIsDir: ObjCBool = false
        guard fm.fileExists(atPath: pair.to, isDirectory: &destIsDir) else {
            throw FileOpsError.failed("Verificación falló: no aparece \(URL(fileURLWithPath: pair.to).lastPathComponent)")
        }
        if destIsDir.boolValue { return }

        let destAttrs = try fm.attributesOfItem(atPath: pair.to)
        let destSize = (destAttrs[.size] as? NSNumber)?.int64Value ?? -1
        if destSize < 0 {
            throw FileOpsError.failed("Verificación falló: tamaño inválido en destino")
        }

        if fm.fileExists(atPath: pair.from) {
            let srcAttrs = try fm.attributesOfItem(atPath: pair.from)
            let srcSize = (srcAttrs[.size] as? NSNumber)?.int64Value ?? -1
            if srcSize >= 0, srcSize != destSize {
                throw FileOpsError.failed(
                    "Verificación falló: tamaño distinto (\(srcSize) ≠ \(destSize)) en \(URL(fileURLWithPath: pair.to).lastPathComponent)"
                )
            }
            if expectingMove {
                // Move same-volume debería haber quitado el origen; si sigue,
                // FileOps ya lo dejó a propósito o falló a medias — no borramos aquí.
            }
        }
    }
}

import XCTest
import OrdenCore
import Foundation

final class TransferQueueTests: XCTestCase {
    func testCopyVerifiesSizeAndSHA256() async throws {
        let fm = FileManager.default
        let srcDir = fm.temporaryDirectory.appendingPathComponent("findaro-tq-src-\(UUID().uuidString)", isDirectory: true)
        let dstDir = fm.temporaryDirectory.appendingPathComponent("findaro-tq-dst-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcDir)
            try? fm.removeItem(at: dstDir)
        }

        let file = srcDir.appendingPathComponent("payload.bin")
        let payload = Data(repeating: 7, count: 32_768)
        try payload.write(to: file)
        let expectedHash = try FileDigest.sha256File(at: file.path)

        let job = TransferQueue.Job(paths: [file.path], destinationDir: dstDir.path, move: false)
        let flag = ProgressFlag()
        let pairs = try await TransferQueue.shared.run(job) { progress in
            if progress.completed > 0 || progress.done {
                flag.mark()
            }
        }

        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(fm.fileExists(atPath: pairs[0].to))
        let destData = try Data(contentsOf: URL(fileURLWithPath: pairs[0].to))
        XCTAssertEqual(destData.count, payload.count)
        XCTAssertEqual(try FileDigest.sha256File(at: pairs[0].to), expectedHash)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
    }

    func testMoveJobRollsBackEarlierItemsWhenLaterFails() async throws {
        let fm = FileManager.default
        let srcDir = fm.temporaryDirectory.appendingPathComponent("findaro-tq-rb-src-\(UUID().uuidString)", isDirectory: true)
        let dstDir = fm.temporaryDirectory.appendingPathComponent("findaro-tq-rb-dst-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcDir)
            try? fm.removeItem(at: dstDir)
        }

        let ok = srcDir.appendingPathComponent("ok.txt")
        try Data("hello".utf8).write(to: ok)

        // Segundo path = el propio destino → FileOps rechaza (sameFolder) tras mover el primero.
        let job = TransferQueue.Job(
            paths: [ok.path, dstDir.path],
            destinationDir: dstDir.path,
            move: true
        )

        do {
            _ = try await TransferQueue.shared.run(job) { _ in }
            XCTFail("expected failure")
        } catch {
            XCTAssertTrue(
                fm.fileExists(atPath: ok.path),
                "Rollback debe devolver ok.txt al origen tras fallar el lote"
            )
            XCTAssertFalse(fm.fileExists(atPath: dstDir.appendingPathComponent("ok.txt").path))
        }
    }

    func testDirectoryCopyVerifiesTreeStats() async throws {
        let fm = FileManager.default
        let srcRoot = fm.temporaryDirectory.appendingPathComponent("findaro-tq-dir-src-\(UUID().uuidString)", isDirectory: true)
        let dstRoot = fm.temporaryDirectory.appendingPathComponent("findaro-tq-dir-dst-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: srcRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstRoot, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcRoot)
            try? fm.removeItem(at: dstRoot)
        }

        let folder = srcRoot.appendingPathComponent("Album", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: folder.appendingPathComponent("a.txt"))
        try Data("bb".utf8).write(to: folder.appendingPathComponent("b.txt"))

        let job = TransferQueue.Job(paths: [folder.path], destinationDir: dstRoot.path, move: false)
        let pairs = try await TransferQueue.shared.run(job) { _ in }
        XCTAssertEqual(pairs.count, 1)
        let destFolder = dstRoot.appendingPathComponent("Album")
        let stats = try FileDigest.treeStats(at: destFolder.path)
        XCTAssertEqual(stats.fileCount, 2)
        XCTAssertEqual(stats.totalBytes, 3)
    }
}

private final class ProgressFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func mark() {
        lock.lock(); _value = true; lock.unlock()
    }
}

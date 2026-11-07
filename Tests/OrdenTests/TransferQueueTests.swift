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

    func testMoveRemovesSourceAfterVerify() async throws {
        let fm = FileManager.default
        let srcDir = fm.temporaryDirectory.appendingPathComponent("findaro-tq-mv-src-\(UUID().uuidString)", isDirectory: true)
        let dstDir = fm.temporaryDirectory.appendingPathComponent("findaro-tq-mv-dst-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcDir)
            try? fm.removeItem(at: dstDir)
        }

        let file = srcDir.appendingPathComponent("move-me.txt")
        try Data("payload".utf8).write(to: file)
        let hash = try FileDigest.sha256File(at: file.path)

        let job = TransferQueue.Job(paths: [file.path], destinationDir: dstDir.path, move: true)
        let pairs = try await TransferQueue.shared.run(job) { _ in }
        XCTAssertEqual(pairs.count, 1)
        XCTAssertFalse(fm.fileExists(atPath: file.path), "MOVE debe eliminar el origen")
        XCTAssertEqual(try FileDigest.sha256File(at: pairs[0].to), hash)
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

    func testDirectoryCopyVerifiesPerFileManifest() async throws {
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
        let expected = try FileDigest.treeManifest(at: folder.path)

        let job = TransferQueue.Job(paths: [folder.path], destinationDir: dstRoot.path, move: false)
        let pairs = try await TransferQueue.shared.run(job) { _ in }
        XCTAssertEqual(pairs.count, 1)
        let destFolder = dstRoot.appendingPathComponent("Album")
        try FileDigest.verifyManifest(expected, at: destFolder.path)
        XCTAssertEqual(expected.fileCount, 2)
        XCTAssertEqual(expected.totalBytes, 3)
    }

    func testAppPackageCopyIncludesInnerFilesInManifest() async throws {
        let fm = FileManager.default
        let srcRoot = fm.temporaryDirectory.appendingPathComponent("findaro-tq-app-src-\(UUID().uuidString)", isDirectory: true)
        let dstRoot = fm.temporaryDirectory.appendingPathComponent("findaro-tq-app-dst-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: srcRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstRoot, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcRoot)
            try? fm.removeItem(at: dstRoot)
        }

        let app = srcRoot.appendingPathComponent("Demo.app", isDirectory: true)
        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: macOS.appendingPathComponent("Demo"))
        try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))

        let expected = try FileDigest.treeManifest(at: app.path)
        XCTAssertGreaterThanOrEqual(expected.fileCount, 2, "Debe hashear interior del .app")

        let job = TransferQueue.Job(paths: [app.path], destinationDir: dstRoot.path, move: false)
        _ = try await TransferQueue.shared.run(job) { _ in }
        try FileDigest.verifyManifest(expected, at: dstRoot.appendingPathComponent("Demo.app").path)
    }

    func testSymlinkIsRecordedWithoutFollowing() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("findaro-tq-link-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let target = root.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: target)
        let link = root.appendingPathComponent("alias.txt")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "real.txt")

        let manifest = try FileDigest.treeManifest(at: root.path)
        XCTAssertTrue(manifest.entries.contains { $0.kind == .symlink && $0.relativePath == "alias.txt" })
        XCTAssertTrue(manifest.entries.contains { $0.kind == .file && $0.relativePath == "real.txt" })
    }

    func testCopyRollbackRemovesPartialDestOnFailure() async throws {
        let fm = FileManager.default
        let srcDir = fm.temporaryDirectory.appendingPathComponent("findaro-tq-cp-rb-src-\(UUID().uuidString)", isDirectory: true)
        let dstDir = fm.temporaryDirectory.appendingPathComponent("findaro-tq-cp-rb-dst-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcDir)
            try? fm.removeItem(at: dstDir)
        }

        let ok = srcDir.appendingPathComponent("ok.txt")
        try Data("hello".utf8).write(to: ok)
        let job = TransferQueue.Job(
            paths: [ok.path, dstDir.path],
            destinationDir: dstDir.path,
            move: false
        )
        do {
            _ = try await TransferQueue.shared.run(job) { _ in }
            XCTFail("expected failure")
        } catch {
            XCTAssertFalse(fm.fileExists(atPath: dstDir.appendingPathComponent("ok.txt").path))
            XCTAssertTrue(fm.fileExists(atPath: ok.path))
        }
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

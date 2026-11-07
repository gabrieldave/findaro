import XCTest
import OrdenCore
import Foundation

final class FolderMergeSafetyTests: XCTestCase {
    func testSameSizeDifferentContentIsConflict() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        let dst = root.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("AAAA".utf8).write(to: src.appendingPathComponent("same.txt"))
        try Data("BBBB".utf8).write(to: dst.appendingPathComponent("same.txt"))
        let preview = FolderMerge.preview(source: src.path, dest: dst.path)
        XCTAssertTrue(preview.isComplete)
        XCTAssertEqual(preview.conflictCount, 1)
    }

    func testMergeKeepsBothAndPreservesSource() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        let dst = root.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("AAAA".utf8).write(to: src.appendingPathComponent("same.txt"))
        try Data("BBBB".utf8).write(to: dst.appendingPathComponent("same.txt"))
        let result = try FolderMerge.mergeCopy(source: src.path, dest: dst.path)
        XCTAssertEqual(result.pairs.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: src.appendingPathComponent("same.txt").path))
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: result.pairs[0].to), encoding: .utf8), "AAAA")
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("same.txt"), encoding: .utf8), "BBBB")
    }

    func testHiddenFilesAndEmptyDirectoriesAreIncluded() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        let dst = root.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: src.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("hidden".utf8).write(to: src.appendingPathComponent(".secret"))
        let preview = FolderMerge.preview(source: src.path, dest: dst.path)
        XCTAssertTrue(preview.isComplete)
        XCTAssertTrue(preview.items.contains { $0.relativePath == ".secret" })
        XCTAssertTrue(preview.items.contains { $0.relativePath == "empty" && $0.sourceIsDirectory })
        let result = try FolderMerge.mergeCopy(source: src.path, dest: dst.path)
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent(".secret").path))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("empty").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(result.pairs.count, 1)
    }

    func testPackageContentsAreIncluded() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        let dst = root.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: src.appendingPathComponent("Sample.app/Contents"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("bundle".utf8).write(to: src.appendingPathComponent("Sample.app/Contents/Info.plist"))
        let preview = FolderMerge.preview(source: src.path, dest: dst.path)
        XCTAssertTrue(preview.items.contains { $0.relativePath == "Sample.app/Contents/Info.plist" })
        let result = try FolderMerge.mergeCopy(source: src.path, dest: dst.path)
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("Sample.app/Contents/Info.plist").path))
        XCTAssertEqual(result.pairs.count, 1)
    }

    func testTypeConflictBlocksMerge() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        let dst = root.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("file".utf8).write(to: src.appendingPathComponent("clash"))
        try fm.createDirectory(at: dst.appendingPathComponent("clash"), withIntermediateDirectories: true)
        let preview = FolderMerge.preview(source: src.path, dest: dst.path)
        XCTAssertFalse(preview.canMerge)
        XCTAssertTrue(preview.hasTypeConflicts)
        XCTAssertThrowsError(try FolderMerge.mergeCopy(source: src.path, dest: dst.path))
    }

    func testTruncatedPreviewBlocksMerge() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        let dst = root.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for i in 0..<3 {
            try Data("x".utf8).write(to: src.appendingPathComponent("\(i).txt"))
        }
        let preview = FolderMerge.preview(source: src.path, dest: dst.path, maxItems: 2)
        XCTAssertFalse(preview.isComplete)
        XCTAssertThrowsError(try FolderMerge.mergeCopy(source: src.path, dest: dst.path, maxItems: 2))
    }

    func testMoveToTrashRequiresUnchangedSourceTree() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        let dst = root.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("original".utf8).write(to: src.appendingPathComponent("a.txt"))
        let result = try FolderMerge.mergeCopy(source: src.path, dest: dst.path)
        try Data("changed".utf8).write(to: src.appendingPathComponent("a.txt"))
        XCTAssertThrowsError(try FolderMerge.trashSourceAfterVerifiedMerge(result))
        XCTAssertTrue(fm.fileExists(atPath: src.appendingPathComponent("a.txt").path))
    }
}

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
        let pairs = try FolderMerge.mergeCopy(source: src.path, dest: dst.path)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: src.appendingPathComponent("same.txt").path))
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: pairs[0].to), encoding: .utf8), "AAAA")
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
    }

    func testTruncatedPreviewBlocksMerge() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let src = root.appendingPathComponent("src", isDirectory: true)
        let dst = root.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for i in 0..<3 { try Data("x".utf8).write(to: src.appendingPathComponent("\(i).txt")) }
        let preview = FolderMerge.preview(source: src.path, dest: dst.path, maxItems: 2)
        XCTAssertFalse(preview.isComplete)
        XCTAssertThrowsError(try FolderMerge.mergeCopy(source: src.path, dest: dst.path))
    }
}

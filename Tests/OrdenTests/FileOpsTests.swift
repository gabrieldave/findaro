import XCTest
import OrdenCore
import Foundation

final class FileOpsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LicenseGate.setWriteAllowed(true)
    }

    func testMoveBetweenFolders() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-ops-\(UUID().uuidString)", isDirectory: true)
        let a = root.appendingPathComponent("a", isDirectory: true)
        let b = root.appendingPathComponent("b", isDirectory: true)
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = a.appendingPathComponent("nota.txt")
        try Data("hola".utf8).write(to: file)
        let pairs = try FileOps.transfer(paths: [file.path], toDirectory: b.path, move: true)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        XCTAssertTrue(fm.fileExists(atPath: b.appendingPathComponent("nota.txt").path))
    }

    func testCreateRenameDuplicate() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-crud-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let folder = try FileOps.createFolder(named: "Nueva", in: root.path)
        XCTAssertTrue(fm.fileExists(atPath: folder))
        let renamed = try FileOps.rename(path: folder, to: "Renombrada")
        XCTAssertEqual(URL(fileURLWithPath: renamed).lastPathComponent, "Renombrada")
        let file = URL(fileURLWithPath: renamed).appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let dup = try FileOps.duplicate(path: file.path)
        XCTAssertTrue(fm.fileExists(atPath: dup))
        XCTAssertNotEqual(dup, file.path)
    }

    func testTransferPreflightsEverySourceBeforeMovingAnything() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-preflight-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let dest = root.appendingPathComponent("dest", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let existing = source.appendingPathComponent("present.txt")
        try Data("keep".utf8).write(to: existing)
        let missing = source.appendingPathComponent("missing.txt")
        XCTAssertThrowsError(try FileOps.transfer(paths: [existing.path, missing.path], toDirectory: dest.path, move: true))
        XCTAssertTrue(fm.fileExists(atPath: existing.path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("present.txt").path))
    }

    func testTransferRejectsMovingFolderIntoItself() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-self-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let nested = source.appendingPathComponent("nested", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        XCTAssertThrowsError(try FileOps.transfer(paths: [source.path], toDirectory: nested.path, move: true))
        XCTAssertTrue(fm.fileExists(atPath: source.path))
    }

    func testCreateFolderRejectsTraversalAndSeparators() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-name-\(UUID().uuidString)", isDirectory: true)
        let parent = root.appendingPathComponent("parent", isDirectory: true)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        XCTAssertThrowsError(try FileOps.createFolder(named: "../escaped", in: parent.path))
        XCTAssertThrowsError(try FileOps.createFolder(named: "nested/name", in: parent.path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("escaped").path))
    }

    func testTrashOpsPermanentlyDeleteOnIsolatedSandbox() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("findaro-qa-trash-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let file1 = root.appendingPathComponent("temp1.txt")
        let file2 = root.appendingPathComponent("temp2.txt")
        try Data("dummy1".utf8).write(to: file1)
        try Data("dummy2".utf8).write(to: file2)

        XCTAssertTrue(fm.fileExists(atPath: file1.path))
        XCTAssertTrue(fm.fileExists(atPath: file2.path))

        let result = try TrashOps.permanentlyDelete(paths: [file1.path, file2.path])
        XCTAssertEqual(result.ok, 2)
        XCTAssertEqual(result.failures.count, 0)
        XCTAssertFalse(fm.fileExists(atPath: file1.path))
        XCTAssertFalse(fm.fileExists(atPath: file2.path))
    }

    func testTrashOpsIsTrashPath() {
        let userTrash = TrashOps.userTrashPath
        XCTAssertTrue(TrashOps.isTrashPath(userTrash))
        XCTAssertFalse(TrashOps.isTrashPath("/Applications"))
        XCTAssertFalse(TrashOps.isTrashPath("/System"))
    }
}

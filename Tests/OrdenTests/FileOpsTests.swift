import XCTest
import OrdenCore
import Foundation

final class FileOpsTests: XCTestCase {
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
}

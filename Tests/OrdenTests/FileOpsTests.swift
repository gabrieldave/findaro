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

        let n = try FileOps.transfer(paths: [file.path], toDirectory: b.path, move: true)
        XCTAssertEqual(n, 1)
        XCTAssertFalse(fm.fileExists(atPath: file.path))
        XCTAssertTrue(fm.fileExists(atPath: b.appendingPathComponent("nota.txt").path))
    }
}

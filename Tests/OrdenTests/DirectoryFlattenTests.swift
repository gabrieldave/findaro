import XCTest
import OrdenCore
import Foundation

final class DirectoryFlattenTests: XCTestCase {
    func testFlattenListsNestedFilesWithoutLeavingRoot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ordena-flat-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try Data("uno".utf8).write(to: root.appendingPathComponent("root.txt"))
        try Data("dos".utf8).write(to: nested.appendingPathComponent("deep.txt"))
        try Data("hide".utf8).write(to: root.appendingPathComponent(".secreto"))

        let visible = try DirectoryFlatten.load(root: root.path, includeHidden: false)
        let names = Set(visible.map(\.name))
        XCTAssertTrue(names.contains("root.txt"))
        XCTAssertTrue(names.contains("deep.txt"))
        XCTAssertFalse(names.contains(".secreto"))

        let withHidden = try DirectoryFlatten.load(root: root.path, includeHidden: true)
        XCTAssertTrue(withHidden.map(\.name).contains(".secreto"))
    }

    func testFlattenDoesNotLoopOnInternalSymlinkToAncestor() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("findaro-flat-cycle-\(UUID().uuidString)", isDirectory: true)
        let child = root.appendingPathComponent("child", isDirectory: true)
        try fm.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try Data("x".utf8).write(to: child.appendingPathComponent("file.txt"))
        let link = child.appendingPathComponent("loop-to-root")
        try fm.createSymbolicLink(at: link, withDestinationURL: root)

        // Sin visitedCanonicalPaths esto podía reentrar hasta maxDepth.
        let entries = try DirectoryFlatten.load(root: root.path, includeHidden: false, maxDepth: 8, maxItems: 100)
        let names = entries.map(\.name)
        XCTAssertEqual(names.filter { $0 == "file.txt" }.count, 1)
        XCTAssertLessThan(entries.count, 20)
    }
}

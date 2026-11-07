import XCTest
import OrdenCore
import Foundation

final class AgentPolicyTests: XCTestCase {
    func testPathBoundaryDoesNotAcceptSiblingPrefix() {
        XCTAssertFalse(AgentPolicy.isSameOrDescendant("/Users/example-other/file.txt", of: "/Users/example"))
        XCTAssertTrue(AgentPolicy.isSameOrDescendant("/Users/example/Documents/file.txt", of: "/Users/example"))
        XCTAssertTrue(AgentPolicy.isSameOrDescendant("/Users/example", of: "/Users/example"))
    }

    func testPathPolicyRejectsEmptyAndSiblingPrefix() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(AgentPolicy.isPathAllowed(home))
        XCTAssertFalse(AgentPolicy.isPathAllowed(home + "-outside"))
        XCTAssertFalse(AgentPolicy.isPathAllowed(""))
    }

    func testPathPolicyRejectsSymlinkEscape() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inside = root.appendingPathComponent("inside", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: inside, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let link = inside.appendingPathComponent("escape")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertFalse(AgentPolicy.isSameOrDescendant(link.path, of: inside.path))
    }
}

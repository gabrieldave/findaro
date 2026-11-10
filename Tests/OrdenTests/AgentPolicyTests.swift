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

    func testPathPolicyAllowsUsersShared() {
        XCTAssertTrue(AgentPolicy.isPathAllowed("/Users/Shared"))
        XCTAssertTrue(AgentPolicy.isPathAllowed("/Users/Shared/FINDARO-Demo/DESTINO/Respaldo Estudio"))
        XCTAssertFalse(AgentPolicy.isPathAllowed("/Users/SharedSomething"))
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

    func testOpenFileRequiresApprovalForExecutablesAndInstallers() {
        XCTAssertEqual(AgentPolicy.risk(for: .openFile, arguments: ["path": "/Users/me/Downloads/Installer.pkg"]), .write)
        XCTAssertEqual(AgentPolicy.risk(for: .openFile, arguments: ["path": "/Users/me/Downloads/Evil.app"]), .write)
        XCTAssertEqual(AgentPolicy.risk(for: .openFile, arguments: ["path": "/Users/me/Downloads/run.command"]), .write)
        XCTAssertEqual(AgentPolicy.risk(for: .openFile, arguments: [:]), .write)
        XCTAssertEqual(AgentPolicy.risk(for: .openFile, arguments: ["path": "/Users/me/Downloads/reporte.pdf"]), .read)
    }
}

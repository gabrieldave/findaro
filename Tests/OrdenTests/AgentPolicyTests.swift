import XCTest
import OrdenCore
import Foundation

final class AgentPolicyTests: XCTestCase {
    func testPathBoundaryDoesNotAcceptSiblingPrefix() {
        XCTAssertFalse(AgentPolicy.isSameOrDescendant("/Users/example-other/file.txt", of: "/Users/example"))
        XCTAssertTrue(AgentPolicy.isSameOrDescendant("/Users/example/Documents/file.txt", of: "/Users/example"))
        XCTAssertTrue(AgentPolicy.isSameOrDescendant("/Users/example", of: "/Users/example"))
    }

    func testAgentAllowsCurrentHomeButNotSiblingPrefix() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(AgentPolicy.isPathAllowed(home))
        XCTAssertFalse(AgentPolicy.isPathAllowed(home + "-outside"))
        XCTAssertFalse(AgentPolicy.isPathAllowed(""))
    }
}

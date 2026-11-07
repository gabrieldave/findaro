import XCTest
import OrdenCore
import Foundation

final class RecursiveSearchSafetyTests: XCTestCase {
    func testSearchDoesNotFollowSymlinkOutsideRoot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-search-\(UUID().uuidString)", isDirectory: true)
        let inside = root.appendingPathComponent("inside", isDirectory: true)
        let outside = root.appendingPathComponent("inside-evil", isDirectory: true)
        try fm.createDirectory(at: inside, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "needle".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: inside.appendingPathComponent("escape"), withDestinationURL: outside)

        var hits: [SearchHit] = []
        RecursiveSearch.run(
            query: .init(text: "needle", root: inside.path, searchContent: true),
            isCancelled: { false },
            onProgress: { _ in },
            onHit: { hits.append($0) }
        )
        XCTAssertTrue(hits.isEmpty)
    }
}

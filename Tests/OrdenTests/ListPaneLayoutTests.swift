import XCTest
@testable import OrdenCore

final class ListPaneLayoutTests: XCTestCase {
    func testBuildsSectionsAndGaps() {
        let folders = [
            makeEntry("A", categoryHint: true),
            makeEntry("B", categoryHint: true)
        ]
        let zips = [
            makeEntry("c.zip", categoryHint: false),
            makeEntry("d.zip", categoryHint: false)
        ]
        // force categories via names
        let entries = [
            FileEntry(path: "/t/A", name: "A", isDirectory: true, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "Folder"),
            FileEntry(path: "/t/B", name: "B", isDirectory: true, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "Folder"),
            FileEntry(path: "/t/c.zip", name: "c.zip", isDirectory: false, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "ZIP"),
            FileEntry(path: "/t/d.zip", name: "d.zip", isDirectory: false, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "ZIP")
        ]
        let rows = ListPaneLayout.build(entries: entries)
        XCTAssertEqual(rows.count, 2 + 2 + 1 + 2) // section+2entries + gap + section+2entries
        if case .section(let cat, let count) = rows[0] {
            XCTAssertEqual(cat, .folder)
            XCTAssertEqual(count, 2)
        } else {
            XCTFail("expected section")
        }
        XCTAssertNotNil(rows.first(where: {
            if case .gap = $0 { return true }
            return false
        }))
        _ = folders; _ = zips
    }

    func testMarqueeSkipsHeadersAndHitsEntries() {
        let entries = [
            FileEntry(path: "/t/A", name: "A", isDirectory: true, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "Folder"),
            FileEntry(path: "/t/c.zip", name: "c.zip", isDirectory: false, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "ZIP")
        ]
        let rows = ListPaneLayout.build(entries: entries)
        let entryH: CGFloat = 48
        let hits = ListPaneLayout.entryIDs(y0: 0, y1: 500, rows: rows, entryRowHeight: entryH)
        XCTAssertEqual(hits, Set(entries.map(\.id)))
    }

    private func makeEntry(_ name: String, categoryHint: Bool) -> FileEntry {
        FileEntry(
            path: "/t/\(name)",
            name: name,
            isDirectory: categoryHint,
            size: 1,
            dateModified: .now,
            dateCreated: .now,
            dateAdded: .now,
            kind: "x"
        )
    }
}

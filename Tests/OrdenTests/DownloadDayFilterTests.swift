import XCTest
@testable import OrdenCore

final class DownloadDayFilterTests: XCTestCase {
    func testTodayAddedIsIncluded() {
        let now = Date()
        let entry = FileEntry(
            path: "/tmp/a.pdf",
            name: "a.pdf",
            isDirectory: false,
            size: 10,
            dateModified: now,
            dateCreated: now.addingTimeInterval(-3600),
            dateAdded: now,
            kind: "PDF"
        )
        XCTAssertTrue(DownloadDayFilter.isActivityToday(entry, now: now))
    }

    func testYesterdayExcluded() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let entry = FileEntry(
            path: "/tmp/old.zip",
            name: "old.zip",
            isDirectory: false,
            size: 10,
            dateModified: yesterday,
            dateCreated: yesterday,
            dateAdded: yesterday,
            kind: "ZIP"
        )
        XCTAssertFalse(DownloadDayFilter.isActivityToday(entry, now: now))
    }

    func testSortNewestFirst() {
        let now = Date()
        let older = now.addingTimeInterval(-100)
        let a = FileEntry(
            path: "/tmp/a", name: "a", isDirectory: false, size: 1,
            dateModified: older, dateCreated: older, dateAdded: older, kind: "x"
        )
        let b = FileEntry(
            path: "/tmp/b", name: "b", isDirectory: false, size: 1,
            dateModified: now, dateCreated: now, dateAdded: now, kind: "x"
        )
        let sorted = DownloadDayFilter.sortNewestFirst([a, b])
        XCTAssertEqual(sorted.first?.name, "b")
    }
}

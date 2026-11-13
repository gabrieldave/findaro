import XCTest
@testable import OrdenCore

final class BreadcrumbSegmentTests: XCTestCase {
    func testHomeFolderDecomposition() {
        let fakeHome = "/Users/testuser"
        let target = "/Users/testuser/Documents/Projects/Findaro"

        let segments = BreadcrumbResolver.segments(for: target, homePath: fakeHome)
        XCTAssertEqual(segments.count, 4)

        XCTAssertEqual(segments[0].title, "~")
        XCTAssertEqual(segments[0].path, "/Users/testuser")
        XCTAssertTrue(segments[0].isHome)
        XCTAssertEqual(segments[0].iconName, "house.fill")

        XCTAssertEqual(segments[1].title, "Documents")
        XCTAssertEqual(segments[1].path, "/Users/testuser/Documents")
        XCTAssertFalse(segments[1].isHome)
        XCTAssertNil(segments[1].iconName)

        XCTAssertEqual(segments[2].title, "Projects")
        XCTAssertEqual(segments[2].path, "/Users/testuser/Documents/Projects")

        XCTAssertEqual(segments[3].title, "Findaro")
        XCTAssertEqual(segments[3].path, "/Users/testuser/Documents/Projects/Findaro")
    }

    func testHomeRootItself() {
        let fakeHome = "/Users/testuser"
        let segments = BreadcrumbResolver.segments(for: fakeHome, homePath: fakeHome)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].title, "~")
        XCTAssertEqual(segments[0].path, fakeHome)
        XCTAssertTrue(segments[0].isHome)
        XCTAssertEqual(segments[0].iconName, "house.fill")
    }

    func testExternalVolumeDecomposition() {
        let target = "/Volumes/ExternalSSD/Backups/2026"
        let segments = BreadcrumbResolver.segments(for: target, homePath: "/Users/someone")

        XCTAssertEqual(segments.count, 3)

        XCTAssertEqual(segments[0].title, "ExternalSSD")
        XCTAssertEqual(segments[0].path, "/Volumes/ExternalSSD")
        XCTAssertTrue(segments[0].isExternalVolume)
        XCTAssertEqual(segments[0].iconName, "externaldrive.fill")

        XCTAssertEqual(segments[1].title, "Backups")
        XCTAssertEqual(segments[1].path, "/Volumes/ExternalSSD/Backups")

        XCTAssertEqual(segments[2].title, "2026")
        XCTAssertEqual(segments[2].path, "/Volumes/ExternalSSD/Backups/2026")
    }

    func testSystemRootDecomposition() {
        let target = "/Library/Application Support/Findaro"
        let segments = BreadcrumbResolver.segments(for: target, homePath: "/Users/someone")

        XCTAssertEqual(segments.count, 4)

        XCTAssertEqual(segments[0].title, "/")
        XCTAssertEqual(segments[0].path, "/")
        XCTAssertEqual(segments[0].iconName, "internaldrive")

        XCTAssertEqual(segments[1].title, "Library")
        XCTAssertEqual(segments[1].path, "/Library")

        XCTAssertEqual(segments[2].title, "Application Support")
        XCTAssertEqual(segments[2].path, "/Library/Application Support")

        XCTAssertEqual(segments[3].title, "Findaro")
        XCTAssertEqual(segments[3].path, "/Library/Application Support/Findaro")
    }

    func testEmptyPathReturnsEmpty() {
        let segments = BreadcrumbResolver.segments(for: "")
        XCTAssertTrue(segments.isEmpty)
    }
}

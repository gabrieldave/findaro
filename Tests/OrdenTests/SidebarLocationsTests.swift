import XCTest
import OrdenCore

final class SidebarLocationsTests: XCTestCase {
    func testSystemVolumeSymlinkIsNotListedTwice() {
        let items = SidebarLocations.make(
            homePath: "/Users/davidai",
            iCloudPath: "/Users/davidai/Library/Mobile Documents/com~apple~CloudDocs",
            cloudFolders: [],
            volumes: [
                .init(name: "Macintosh HD", path: "/Volumes/Macintosh HD", resolvedPath: "/"),
                .init(name: "Ordena 0.1.2-arm64", path: "/Volumes/Ordena 0.1.2-arm64", resolvedPath: "/Volumes/Ordena 0.1.2-arm64")
            ],
            trashPath: "/Users/davidai/.Trash"
        )

        let titles = items.map(\.title)
        XCTAssertEqual(titles.filter { $0 == "Macintosh HD" }.count, 1)
        XCTAssertTrue(titles.contains("Ordena 0.1.2-arm64"))
        XCTAssertEqual(titles.filter { $0 == "iCloud Drive" }.count, 1)
        XCTAssertEqual(titles.last, "Basurero")
    }

    func testTwoGoogleAccountsGetDistinctTitles() {
        let items = SidebarLocations.make(
            homePath: "/Users/davidai",
            iCloudPath: nil,
            cloudFolders: [
                .init(name: "GoogleDrive-david.del.rio.colin@gmail.com", path: "/cloud/david"),
                .init(name: "GoogleDrive-feekwakjisan@gmail.com", path: "/cloud/feek")
            ],
            volumes: [],
            trashPath: nil
        )

        let titles = items.map(\.title)
        XCTAssertTrue(titles.contains("Google Drive · david.del.rio.colin@gmail.com"))
        XCTAssertTrue(titles.contains("Google Drive · feekwakjisan@gmail.com"))
        XCTAssertEqual(titles.filter { $0.hasPrefix("Google Drive") }.count, 2)
    }

    func testSingleGoogleDriveKeepsPlainName() {
        let items = SidebarLocations.make(
            homePath: "/Users/ana",
            iCloudPath: nil,
            cloudFolders: [
                .init(name: "GoogleDrive-ana@gmail.com", path: "/cloud/ana")
            ],
            volumes: [],
            trashPath: nil
        )

        XCTAssertTrue(items.map(\.title).contains("Google Drive"))
        XCTAssertFalse(items.contains { $0.title.contains("@") })
    }
}

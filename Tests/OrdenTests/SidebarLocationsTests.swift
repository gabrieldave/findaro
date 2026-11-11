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
        XCTAssertEqual(titles.last, L10n.s("Papelera", "Trash"))
    }

    func testTwoGoogleAccountsGetDistinctTitlesWithoutEmails() {
        let items = SidebarLocations.make(
            homePath: "/Users/davidai",
            iCloudPath: nil,
            cloudFolders: [
                .init(name: "GoogleDrive-david.del.rio.colin@gmail.com", path: "/cloud/david"),
                .init(name: "GoogleDrive-feekwakjisan@gmail.com", path: "/cloud/feek")
            ],
            volumes: [],
            trashPath: nil,
            demoMode: false
        )

        let titles = items.map(\.title)
        XCTAssertTrue(titles.contains("Google Drive 1"))
        XCTAssertTrue(titles.contains("Google Drive 2"))
        XCTAssertFalse(items.contains { $0.title.contains("@") })
    }

    func testSingleGoogleDriveKeepsPlainName() {
        let items = SidebarLocations.make(
            homePath: "/Users/ana",
            iCloudPath: nil,
            cloudFolders: [
                .init(name: "GoogleDrive-ana@gmail.com", path: "/cloud/ana")
            ],
            volumes: [],
            trashPath: nil,
            demoMode: false
        )

        XCTAssertTrue(items.map(\.title).contains("Google Drive"))
        XCTAssertFalse(items.contains { $0.title.contains("@") })
    }

    func testRecoveryVolumeIsExcluded() {
        let items = SidebarLocations.make(
            homePath: "/Users/demo",
            iCloudPath: nil,
            cloudFolders: [],
            volumes: [
                .init(name: "Recovery", path: "/Volumes/Recovery", resolvedPath: "/Volumes/Recovery"),
                .init(name: "Datos", path: "/Volumes/Datos", resolvedPath: "/Volumes/Datos")
            ],
            trashPath: nil,
            demoMode: false
        )
        let titles = items.map(\.title)
        XCTAssertFalse(titles.contains("Recovery"))
        XCTAssertTrue(titles.contains("Datos"))
    }

    func testDemoModeHidesHomeAndClouds() {
        let items = SidebarLocations.make(
            homePath: "/Users/daveax",
            iCloudPath: "/Users/daveax/Library/Mobile Documents/com~apple~CloudDocs",
            cloudFolders: [
                .init(name: "GoogleDrive-x@y.com", path: "/cloud/x")
            ],
            volumes: [
                .init(name: "Recovery", path: "/Volumes/Recovery", resolvedPath: "/Volumes/Recovery")
            ],
            trashPath: "/Users/daveax/.Trash",
            demoMode: true
        )
        let titles = items.map(\.title)
        XCTAssertFalse(titles.contains("daveax"))
        XCTAssertFalse(titles.contains("iCloud Drive"))
        XCTAssertFalse(titles.contains("Google Drive"))
        XCTAssertFalse(titles.contains("Recovery"))
        XCTAssertTrue(titles.contains("Macintosh HD"))
        XCTAssertEqual(titles.last, L10n.s("Papelera", "Trash"))
    }
}

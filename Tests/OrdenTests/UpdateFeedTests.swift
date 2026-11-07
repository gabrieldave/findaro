import XCTest
import OrdenCore

final class UpdateFeedTests: XCTestCase {
    private let feed = UpdateFeed.PublicFeed(
        version: "0.1.80",
        tag: "v0.1.80",
        dmg_url: "https://ordena.iareal.net/downloads/Ordena-0.1.80-arm64.dmg",
        notes_url: "https://ordena.iareal.net/",
        sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        findaro_dmg_url: "https://ordena.iareal.net/downloads/Findaro-0.1.80-arm64.dmg",
        findaro_sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    )

    func testFindaroChannelUsesExclusiveFindaroURLAndHash() throws {
        let release = try UpdateFeed.resolve(feed: feed, installedBundleID: UpdateFeed.findaroBundleID)
        XCTAssertEqual(release.expectedBundleID, UpdateFeed.findaroBundleID)
        XCTAssertEqual(release.dmgURL.absoluteString, feed.findaro_dmg_url)
        XCTAssertEqual(release.sha256, feed.findaro_sha256)
        XCTAssertFalse(release.dmgURL.absoluteString.contains("Ordena"))
    }

    func testOrdenaChannelUsesExclusiveOrdenaURLAndHash() throws {
        let release = try UpdateFeed.resolve(feed: feed, installedBundleID: UpdateFeed.ordenaBundleID)
        XCTAssertEqual(release.expectedBundleID, UpdateFeed.ordenaBundleID)
        XCTAssertEqual(release.dmgURL.absoluteString, feed.dmg_url)
        XCTAssertEqual(release.sha256, feed.sha256)
        XCTAssertFalse(release.dmgURL.absoluteString.contains("Findaro"))
    }

    func testFindaroRejectsFeedWithoutFindaroChannel() {
        let incomplete = UpdateFeed.PublicFeed(
            version: "0.1.80",
            dmg_url: feed.dmg_url,
            notes_url: feed.notes_url,
            sha256: feed.sha256
        )
        XCTAssertThrowsError(
            try UpdateFeed.resolve(feed: incomplete, installedBundleID: UpdateFeed.findaroBundleID)
        )
    }

    func testOrdenaRejectsFeedWithoutSHA() {
        let incomplete = UpdateFeed.PublicFeed(
            version: "0.1.80",
            dmg_url: feed.dmg_url,
            notes_url: feed.notes_url,
            sha256: nil,
            findaro_dmg_url: feed.findaro_dmg_url,
            findaro_sha256: feed.findaro_sha256
        )
        XCTAssertThrowsError(
            try UpdateFeed.resolve(feed: incomplete, installedBundleID: UpdateFeed.ordenaBundleID)
        )
    }

    func testRejectsUnknownBundleAndNonHTTPS() {
        XCTAssertThrowsError(
            try UpdateFeed.resolve(feed: feed, installedBundleID: "com.example.other")
        )
        var bad = feed
        bad.findaro_dmg_url = "http://ordena.iareal.net/downloads/x.dmg"
        XCTAssertThrowsError(
            try UpdateFeed.resolve(feed: bad, installedBundleID: UpdateFeed.findaroBundleID)
        )
    }

    func testVersionCompare() {
        XCTAssertTrue(UpdateFeed.isVersion("0.1.80", newerThan: "0.1.79"))
        XCTAssertFalse(UpdateFeed.isVersion("0.1.79", newerThan: "0.1.80"))
        XCTAssertFalse(UpdateFeed.isVersion("0.1.80", newerThan: "0.1.80"))
    }
}

import XCTest
import CryptoKit
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

    func testVerifiedFeedAcceptsValidSignature() throws {
        let ephemeralPrivate = Curve25519.Signing.PrivateKey()
        let ephemeralPublicHex = ephemeralPrivate.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()

        let feedJSON = """
        {
          "version": "0.1.113",
          "tag": "v0.1.113",
          "dmg_url": "https://ordena.iareal.net/downloads/Ordena-0.1.113-arm64.dmg",
          "notes_url": "https://ordena.iareal.net/",
          "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "findaro_dmg_url": "https://ordena.iareal.net/downloads/Findaro-0.1.113-arm64.dmg",
          "findaro_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
        """
        let data = feedJSON.data(using: .utf8)!
        let signature = try ephemeralPrivate.signature(for: data)

        let parsed = try UpdateFeed.verifiedFeed(data: data, signature: signature, publicKeyHex: ephemeralPublicHex)
        XCTAssertEqual(parsed.version, "0.1.113")
        XCTAssertEqual(parsed.findaro_sha256, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")

        // También verifica con conveniencia Base64
        let b64 = signature.base64EncodedString()
        let parsedB64 = try UpdateFeed.verifiedFeed(data: data, signatureBase64: b64, publicKeyHex: ephemeralPublicHex)
        XCTAssertEqual(parsedB64.version, "0.1.113")
    }

    func testVerifiedFeedRejectsModifiedJSON() throws {
        let ephemeralPrivate = Curve25519.Signing.PrivateKey()
        let ephemeralPublicHex = ephemeralPrivate.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()

        let feedJSON = """
        {"version":"0.1.113","dmg_url":"https://ordena.iareal.net/d.dmg","notes_url":"https://ordena.iareal.net/","sha256":"aaa","findaro_dmg_url":"https://ordena.iareal.net/f.dmg","findaro_sha256":"bbb"}
        """
        var data = feedJSON.data(using: .utf8)!
        let signature = try ephemeralPrivate.signature(for: data)

        // Modificar exactamente 1 byte
        data[data.count / 2] ^= 0xFF

        XCTAssertThrowsError(
            try UpdateFeed.verifiedFeed(data: data, signature: signature, publicKeyHex: ephemeralPublicHex)
        ) { error in
            guard let feedError = error as? UpdateFeed.FeedError else {
                XCTFail("Se esperaba FeedError, se obtuvo: \(error)")
                return
            }
            XCTAssertEqual(feedError, .invalidSignature)
        }
    }

    func testVerifiedFeedRejectsMissingOrEmptySignature() throws {
        let ephemeralPrivate = Curve25519.Signing.PrivateKey()
        let ephemeralPublicHex = ephemeralPrivate.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()

        let feedJSON = """
        {"version":"0.1.113","dmg_url":"https://ordena.iareal.net/d.dmg","notes_url":"https://ordena.iareal.net/","sha256":"aaa","findaro_dmg_url":"https://ordena.iareal.net/f.dmg","findaro_sha256":"bbb"}
        """
        let data = feedJSON.data(using: .utf8)!

        // Firma vacía en Data
        XCTAssertThrowsError(
            try UpdateFeed.verifiedFeed(data: data, signature: Data(), publicKeyHex: ephemeralPublicHex)
        ) { error in
            guard let feedError = error as? UpdateFeed.FeedError else {
                XCTFail("Se esperaba FeedError, se obtuvo: \(error)")
                return
            }
            XCTAssertEqual(feedError, .missingSignature)
        }

        // Firma Base64 vacía o con espacios
        XCTAssertThrowsError(
            try UpdateFeed.verifiedFeed(data: data, signatureBase64: "   ", publicKeyHex: ephemeralPublicHex)
        ) { error in
            guard let feedError = error as? UpdateFeed.FeedError else {
                XCTFail("Se esperaba FeedError, se obtuvo: \(error)")
                return
            }
            XCTAssertEqual(feedError, .missingSignature)
        }
    }

    func testVerifiedFeedRejectsSignatureFromAnotherKey() throws {
        let key1 = Curve25519.Signing.PrivateKey()
        let key2 = Curve25519.Signing.PrivateKey()
        let key2PublicHex = key2.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()

        let feedJSON = """
        {"version":"0.1.113","dmg_url":"https://ordena.iareal.net/d.dmg","notes_url":"https://ordena.iareal.net/","sha256":"aaa","findaro_dmg_url":"https://ordena.iareal.net/f.dmg","findaro_sha256":"bbb"}
        """
        let data = feedJSON.data(using: .utf8)!
        let signatureFromKey1 = try key1.signature(for: data)

        XCTAssertThrowsError(
            try UpdateFeed.verifiedFeed(data: data, signature: signatureFromKey1, publicKeyHex: key2PublicHex)
        ) { error in
            guard let feedError = error as? UpdateFeed.FeedError else {
                XCTFail("Se esperaba FeedError, se obtuvo: \(error)")
                return
            }
            XCTAssertEqual(feedError, .invalidSignature)
        }
    }

    func testAntiDegradationRejectsEqualOrLowerVersion() {
        // Versión menor que instalada -> no ofrece actualización
        XCTAssertFalse(UpdateFeed.isVersion("0.1.112", newerThan: "0.1.113"))
        XCTAssertFalse(UpdateFeed.isVersion("0.1.111", newerThan: "0.1.112"))
        XCTAssertFalse(UpdateFeed.isVersion("0.1.80", newerThan: "0.1.100"))

        // Versión igual a la instalada -> no ofrece actualización
        XCTAssertFalse(UpdateFeed.isVersion("0.1.113", newerThan: "0.1.113"))
        XCTAssertFalse(UpdateFeed.isVersion("0.1.112", newerThan: "0.1.112"))

        // Solo versión estrictamente mayor ofrece actualización
        XCTAssertTrue(UpdateFeed.isVersion("0.1.113", newerThan: "0.1.112"))
        XCTAssertTrue(UpdateFeed.isVersion("0.2.0", newerThan: "0.1.113"))
        XCTAssertTrue(UpdateFeed.isVersion("1.0.0", newerThan: "0.1.113"))
    }
}

import XCTest
@testable import OrdenCore

final class FileDigestTests: XCTestCase {
    func testTreeManifestIncludesHiddenFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "findaro-digest-hidden-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try Data("SECRET=1\n".utf8).write(to: root.appendingPathComponent(".env"))
        try Data("*.log\n".utf8).write(to: root.appendingPathComponent(".gitignore"))
        try Data("visible\n".utf8).write(to: root.appendingPathComponent("readme.txt"))

        let manifest = try FileDigest.treeManifest(at: root.path)
        let paths = Set(manifest.entries.map(\.relativePath))

        XCTAssertTrue(paths.contains(".env"), "El manifiesto debe incluir .env")
        XCTAssertTrue(paths.contains(".gitignore"), "El manifiesto debe incluir .gitignore")
        XCTAssertTrue(paths.contains("readme.txt"))
        XCTAssertEqual(manifest.fileCount, 3)
    }

    func testVerifyManifestDetectsMissingHiddenFile() throws {
        let fm = FileManager.default
        let src = fm.temporaryDirectory.appendingPathComponent(
            "findaro-digest-miss-src-\(UUID().uuidString)",
            isDirectory: true
        )
        let dst = fm.temporaryDirectory.appendingPathComponent(
            "findaro-digest-miss-dst-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: src)
            try? fm.removeItem(at: dst)
        }

        try Data("a=1\n".utf8).write(to: src.appendingPathComponent(".env"))
        try Data("ok\n".utf8).write(to: src.appendingPathComponent("app.txt"))
        try Data("ok\n".utf8).write(to: dst.appendingPathComponent("app.txt"))
        // Destino sin .env

        let expected = try FileDigest.treeManifest(at: src.path)
        XCTAssertTrue(expected.entries.contains { $0.relativePath == ".env" })

        XCTAssertThrowsError(try FileDigest.verifyManifest(expected, at: dst.path)) { error in
            let message = String(describing: error)
            XCTAssertTrue(
                message.contains("integridad") || message.contains("manifiesto") || message.contains("Manifiesto"),
                "Error esperado de integridad, got: \(message)"
            )
        }
    }

    func testVerifyManifestDetectsModifiedHiddenFile() throws {
        let fm = FileManager.default
        let src = fm.temporaryDirectory.appendingPathComponent(
            "findaro-digest-mod-src-\(UUID().uuidString)",
            isDirectory: true
        )
        let dst = fm.temporaryDirectory.appendingPathComponent(
            "findaro-digest-mod-dst-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: src)
            try? fm.removeItem(at: dst)
        }

        try Data("original\n".utf8).write(to: src.appendingPathComponent(".gitignore"))
        try Data("tampered\n".utf8).write(to: dst.appendingPathComponent(".gitignore"))

        let expected = try FileDigest.treeManifest(at: src.path)
        XCTAssertThrowsError(try FileDigest.verifyManifest(expected, at: dst.path))
    }
}

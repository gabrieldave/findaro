import XCTest
@testable import OrdenCore

final class ArchiveOpsTests: XCTestCase {
    func testStemStripsCompoundExtensions() {
        XCTAssertEqual(ArchiveOps.archiveStem(for: "/tmp/pack.tar.gz"), "pack")
        XCTAssertEqual(ArchiveOps.archiveStem(for: "/tmp/pack.tgz"), "pack")
        XCTAssertEqual(ArchiveOps.archiveStem(for: "/tmp/fotos.zip"), "fotos")
    }

    func testIsExtractableZipAndTar() {
        XCTAssertTrue(ArchiveOps.isExtractable("/tmp/a.zip"))
        XCTAssertTrue(ArchiveOps.isExtractable("/tmp/a.tar"))
        XCTAssertTrue(ArchiveOps.isExtractable("/tmp/a.tar.gz"))
        XCTAssertFalse(ArchiveOps.isExtractable("/tmp/a.rar"))
        XCTAssertFalse(ArchiveOps.isExtractable("/tmp/a.7z"))
        XCTAssertFalse(ArchiveOps.isExtractable("/tmp/a.pdf"))
    }

    func testExtractZipStaysBesideArchive() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("findaro-archive-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let inner = root.appendingPathComponent("hola", isDirectory: true)
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        try "hola".write(to: inner.appendingPathComponent("nota.txt"), atomically: true, encoding: .utf8)

        let zipPath = root.appendingPathComponent("paquete.zip").path
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = root
        zip.arguments = ["-r", "paquete.zip", "hola"]
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)
        try fm.removeItem(at: inner)

        let result = try ArchiveOps.extract(archivePath: zipPath)
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: result, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertEqual(URL(fileURLWithPath: result).lastPathComponent, "hola")
        XCTAssertTrue(fm.fileExists(atPath: (result as NSString).appendingPathComponent("nota.txt")))
        XCTAssertTrue(fm.fileExists(atPath: zipPath), "el zip original se conserva")
    }
}

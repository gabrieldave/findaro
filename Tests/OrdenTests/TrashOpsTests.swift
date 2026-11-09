import XCTest
@testable import OrdenCore
import Foundation

final class TrashOpsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LicenseGate.setWriteAllowed(true)
    }

    /// Carpetas de solo lectura (cachés de Go/npm) y archivos con candado se borran sin pedir
    /// nada a Finder: antes cada fallo lanzaba un `osascript` por archivo (cientos de avisos).
    func testPermanentlyDeleteHandlesReadOnlyFoldersAndLockedFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("trash-ro-\(UUID().uuidString)", isDirectory: true)
        let inner = root.appendingPathComponent("cache/mod", isDirectory: true)
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        let file = inner.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        try fm.setAttributes([.immutable: true], ofItemAtPath: file.path)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: inner.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inner.path)
            try? fm.setAttributes([.immutable: false], ofItemAtPath: file.path)
            try? fm.removeItem(at: root)
        }

        let target = root.appendingPathComponent("cache").path
        let result = try TrashOps.permanentlyDelete(paths: [target])
        XCTAssertEqual(result.ok, 1, "Fallos: \(result.failures)")
        XCTAssertFalse(fm.fileExists(atPath: target))
    }

    /// Un nombre de archivo con comillas no puede inyectar AppleScript (antes se interpolaba).
    func testAppleScriptArgumentsAreNotInterpolated() {
        let evil = "/tmp/x\" & (do shell script \"touch /tmp/findaro-pwned\") & \""
        let r = TrashOps.runOSAScript("on run argv\nreturn item 1 of argv\nend run", arguments: [evil])
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines), evil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/findaro-pwned"))
    }
}

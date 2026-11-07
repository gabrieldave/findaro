import XCTest
import OrdenCore
import Foundation

final class FolderWatcherTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory
            .appendingPathComponent("ordena-watcher-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testNotifiesWhenAFileIsDownloadedIntoWatchedFolder() throws {
        let fm = FileManager.default
        let directory = try makeTempDirectory()
        defer { try? fm.removeItem(at: directory) }

        let watcher = FolderWatcher()
        defer { watcher.stop() }

        let changed = expectation(description: "FSEvents notifica el archivo nuevo")
        changed.assertForOverFulfill = false
        watcher.onChange = {
            changed.fulfill()
        }
        watcher.watch(path: directory.path)

        let downloadedFile = directory.appendingPathComponent("descarga-prueba.txt")
        try Data("descarga completa".utf8).write(to: downloadedFile)

        wait(for: [changed], timeout: 5.0)
        XCTAssertTrue(fm.fileExists(atPath: downloadedFile.path))
    }

    func testNotifiesBrowserStyleDownloadRename() throws {
        let fm = FileManager.default
        let directory = try makeTempDirectory()
        defer { try? fm.removeItem(at: directory) }

        let watcher = FolderWatcher()
        defer { watcher.stop() }

        let changed = expectation(description: "FSEvents notifica create+rename tipo Chrome")
        changed.assertForOverFulfill = false
        watcher.onChange = { changed.fulfill() }
        watcher.watch(path: directory.path)

        // Patrón típico de descarga: .crdownload → nombre final.
        let partial = directory.appendingPathComponent("informe.pdf.crdownload")
        let finalURL = directory.appendingPathComponent("informe.pdf")
        try Data("parcial".utf8).write(to: partial)
        try fm.moveItem(at: partial, to: finalURL)

        wait(for: [changed], timeout: 5.0)
        XCTAssertTrue(fm.fileExists(atPath: finalURL.path))
        XCTAssertFalse(fm.fileExists(atPath: partial.path))
    }

    func testNotifiesOnRenameAndDelete() throws {
        let fm = FileManager.default
        let directory = try makeTempDirectory()
        defer { try? fm.removeItem(at: directory) }

        let existing = directory.appendingPathComponent("viejo.txt")
        try Data("hola".utf8).write(to: existing)

        let watcher = FolderWatcher()
        defer { watcher.stop() }

        let renamed = expectation(description: "FSEvents notifica rename")
        renamed.assertForOverFulfill = false
        watcher.onChange = { renamed.fulfill() }
        watcher.watch(path: directory.path)

        let renamedURL = directory.appendingPathComponent("nuevo.txt")
        try fm.moveItem(at: existing, to: renamedURL)
        wait(for: [renamed], timeout: 5.0)

        let deleted = expectation(description: "FSEvents notifica delete")
        deleted.assertForOverFulfill = false
        watcher.onChange = { deleted.fulfill() }
        try fm.removeItem(at: renamedURL)
        wait(for: [deleted], timeout: 5.0)
    }

    func testNotifiesDuringContinuousWriteBurst() throws {
        let fm = FileManager.default
        let directory = try makeTempDirectory()
        defer { try? fm.removeItem(at: directory) }

        let watcher = FolderWatcher()
        defer { watcher.stop() }

        let changed = expectation(description: "FSEvents fuerza refresco en burst largo")
        changed.assertForOverFulfill = false
        changed.expectedFulfillmentCount = 1
        watcher.onChange = { changed.fulfill() }
        watcher.watch(path: directory.path)

        let file = directory.appendingPathComponent("descarga-larga.bin")
        fm.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        // Escritura continua > maxInterval para comprobar que no se “traga” el evento.
        for i in 0..<40 {
            try handle.write(contentsOf: Data(repeating: UInt8(i % 255), count: 4096))
            try handle.synchronize()
            Thread.sleep(forTimeInterval: 0.04)
        }

        wait(for: [changed], timeout: 8.0)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
    }

    func testRewatchSamePathIsIdempotent() throws {
        let fm = FileManager.default
        let directory = try makeTempDirectory()
        defer { try? fm.removeItem(at: directory) }

        let watcher = FolderWatcher()
        defer { watcher.stop() }
        watcher.watch(path: directory.path)
        watcher.watch(path: directory.path)

        let changed = expectation(description: "sigue notificando tras rewatch")
        changed.assertForOverFulfill = false
        watcher.onChange = { changed.fulfill() }

        try Data("x".utf8).write(to: directory.appendingPathComponent("idem.txt"))
        wait(for: [changed], timeout: 5.0)
    }
}

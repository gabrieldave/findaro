import XCTest
import OrdenCore
import Foundation

final class FolderWatcherTests: XCTestCase {
    func testNotifiesWhenAFileIsDownloadedIntoWatchedFolder() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory
            .appendingPathComponent("ordena-watcher-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
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
}

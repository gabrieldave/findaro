import XCTest
import OrdenCore
import Foundation

final class FolderSizerTests: XCTestCase {
    func testFormatNonZero() {
        let s = FolderSizer.format(1_500_000)
        XCTAssertFalse(s.isEmpty)
    }

    func testMeasureTempFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orden-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("a.bin")
        let data = Data(repeating: 7, count: 4096)
        try data.write(to: file)

        let size = FolderSizer.measure(path: file.path, isDirectory: false)
        XCTAssertEqual(size, 4096)

        let folderSize = FolderSizer.measure(path: dir.path, isDirectory: true)
        XCTAssertGreaterThanOrEqual(folderSize, 4096)
    }
}

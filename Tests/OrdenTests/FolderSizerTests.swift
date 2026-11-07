import XCTest
import OrdenCore
import Foundation

final class FolderSizerTests: XCTestCase {
    func testFormatNonZero() {
        XCTAssertFalse(FolderSizer.format(1_500_000).isEmpty)
    }

    func testMeasureTempFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orden-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("a.bin")
        try Data(repeating: 7, count: 4096).write(to: file)
        XCTAssertEqual(FolderSizer.measure(path: file.path, isDirectory: false), 4096)
        XCTAssertGreaterThanOrEqual(FolderSizer.measure(path: dir.path, isDirectory: true), 4096)
    }

    func testMeasureIncludesHiddenFilesAndPackageContents() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("orden-size-hidden-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("Sample.app/Contents"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try Data(repeating: 1, count: 100).write(to: dir.appendingPathComponent(".hidden"))
        try Data(repeating: 2, count: 200).write(to: dir.appendingPathComponent("Sample.app/Contents/data"))
        let result = FolderSizer.measureDirectoryDetailed(at: dir.path)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.bytes, 300)
    }
}

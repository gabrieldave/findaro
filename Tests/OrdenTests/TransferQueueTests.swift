import XCTest
import OrdenCore
import Foundation

final class TransferQueueTests: XCTestCase {
    func testCopyVerifiesSizeAndReportsProgress() async throws {
        let fm = FileManager.default
        let srcDir = fm.temporaryDirectory.appendingPathComponent("ordena-tq-src-\(UUID().uuidString)", isDirectory: true)
        let dstDir = fm.temporaryDirectory.appendingPathComponent("ordena-tq-dst-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcDir)
            try? fm.removeItem(at: dstDir)
        }

        let file = srcDir.appendingPathComponent("payload.bin")
        let payload = Data(repeating: 7, count: 32_768)
        try payload.write(to: file)

        let job = TransferQueue.Job(paths: [file.path], destinationDir: dstDir.path, move: false)
        let flag = ProgressFlag()
        let pairs = try await TransferQueue.shared.run(job) { progress in
            if progress.completed > 0 || progress.done {
                flag.mark()
            }
        }

        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(flag.value)
        XCTAssertTrue(fm.fileExists(atPath: pairs[0].to))
        let destData = try Data(contentsOf: URL(fileURLWithPath: pairs[0].to))
        XCTAssertEqual(destData.count, payload.count)
        XCTAssertTrue(fm.fileExists(atPath: file.path))
    }
}

private final class ProgressFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func mark() {
        lock.lock(); _value = true; lock.unlock()
    }
}

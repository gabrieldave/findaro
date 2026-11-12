import XCTest
@testable import OrdenCore

final class BatchRenameExecutionAndHygieneTests: XCTestCase {
    func testChainRenameAndCaseChangeExecuteAndUndoCleanly() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("FindaroExecTest_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let file1 = dir.appendingPathComponent("step_1.txt")
        let file2 = dir.appendingPathComponent("step_2.txt")
        let upperFile = dir.appendingPathComponent("README.MD")

        try "uno".write(to: file1, atomically: true, encoding: .utf8)
        try "dos".write(to: file2, atomically: true, encoding: .utf8)
        try "guia".write(to: upperFile, atomically: true, encoding: .utf8)

        let engine = BatchRenameEngine()
        let executor = BatchRenameExecutor()

        // 1. Chain rename: step_1 -> step_2 y step_2 -> step_3 sin pisarse
        let chainPreview = engine.preview(
            urls: [file1, file2],
            rules: [.sequential(baseName: "step", startAt: 2, paddingDigits: 1, separator: "_")]
        )
        let tx = try executor.execute(previewItems: chainPreview, fileManager: fm)

        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("step_2.txt"), encoding: .utf8), "uno")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("step_3.txt"), encoding: .utf8), "dos")
        XCTAssertFalse(fm.fileExists(atPath: file1.path))

        // 2. Undo restaura exactamente contenidos y nombres originales
        try executor.undo(tx, fileManager: fm)
        XCTAssertEqual(try String(contentsOf: file1, encoding: .utf8), "uno")
        XCTAssertEqual(try String(contentsOf: file2, encoding: .utf8), "dos")

        // 3. Cambio de mayúsculas a minúsculas en APFS
        let casePreview = engine.preview(
            urls: [upperFile],
            rules: [.changeCase(.lowercase)]
        )
        _ = try executor.execute(previewItems: casePreview, fileManager: fm)
        let namesOnDisk = try fm.contentsOfDirectory(atPath: dir.path)
        // El motor solo cambia el stem y preserva la extensión original ("MD").
        XCTAssertTrue(namesOnDisk.contains("readme.MD"))
        XCTAssertFalse(namesOnDisk.contains("README.MD"))
    }

    func testPurgeDSStorePreservesLegitimateDotfiles() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("FindaroHygieneTest_\(UUID().uuidString)", isDirectory: true)
        let sub = dir.appendingPathComponent("Sub", isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try Data().write(to: dir.appendingPathComponent(".DS_Store"))
        try Data().write(to: sub.appendingPathComponent("._photo.jpg"))
        try Data().write(to: dir.appendingPathComponent(".gitignore"))
        try Data().write(to: sub.appendingPathComponent("photo.jpg"))

        let policy = VolumeHygienePolicy()
        let removed = policy.purgeDSStoreAndAppleDouble(in: dir, recursive: true, fileManager: fm)

        XCTAssertEqual(removed, 2)
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent(".gitignore").path))
        XCTAssertTrue(fm.fileExists(atPath: sub.appendingPathComponent("photo.jpg").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent(".DS_Store").path))
        XCTAssertFalse(fm.fileExists(atPath: sub.appendingPathComponent("._photo.jpg").path))
    }
}

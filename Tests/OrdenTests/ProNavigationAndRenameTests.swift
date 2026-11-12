import XCTest
@testable import OrdenCore

final class ProNavigationAndRenameTests: XCTestCase {
    func testSequentialRenamePreservesExtensionsAndDotfiles() {
        let engine = BatchRenameEngine()
        let urls = [
            URL(fileURLWithPath: "/tmp/DSC_0091.RAW"),
            URL(fileURLWithPath: "/tmp/DSC_0092.jpg"),
            URL(fileURLWithPath: "/tmp/.gitignore")
        ]

        let items = engine.preview(
            urls: urls,
            rules: [.sequential(baseName: "shoot", startAt: 1, paddingDigits: 3, separator: "_")]
        )

        XCTAssertEqual(items[0].proposedName, "shoot_001.RAW")
        XCTAssertEqual(items[1].proposedName, "shoot_002.jpg")
        XCTAssertEqual(items[2].proposedName, "shoot_003")
        XCTAssertTrue(items.allSatisfy { $0.conflict == nil })
    }

    func testDetectsCaseInsensitiveBatchDuplicates() {
        let engine = BatchRenameEngine()
        let urls = [
            URL(fileURLWithPath: "/tmp/Report_A.pdf"),
            URL(fileURLWithPath: "/tmp/report_b.PDF")
        ]

        let items = engine.preview(
            urls: urls,
            rules: [
                .regexReplace(pattern: "_[aAbB]$", template: "")
            ]
        )

        XCTAssertEqual(items[0].conflict, .duplicateInBatch)
        XCTAssertEqual(items[1].conflict, .duplicateInBatch)
    }

    func testPathResolverAndAutocompleteSkipsDSStore() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("FindaroPathTest_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        try fm.createDirectory(at: base.appendingPathComponent("Projects", isDirectory: true), withIntermediateDirectories: false)
        try fm.createDirectory(at: base.appendingPathComponent("Photos", isDirectory: true), withIntermediateDirectories: false)
        try Data().write(to: base.appendingPathComponent(".DS_Store"))
        try Data().write(to: base.appendingPathComponent("Projects_note.txt"))

        let resolver = PathBarResolver()
        let matches = resolver.autocompleteDirectories(for: base.appendingPathComponent("P").path)

        XCTAssertEqual(matches.map(\.lastPathComponent), ["Photos", "Projects"])
        XCTAssertEqual(resolver.resolve(input: base.path), .directory(base.standardizedFileURL))
    }

    func testPreferencesStorePersistsUseNativeAppKitListAndDefaultsTrueForLegacyJSON() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("FindaroPrefsTest_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // 1. JSON legado sin `useNativeAppKitList` debe decodificar como `true`
        let legacyFile = dir.appendingPathComponent("legacy.json")
        try #"{"schemaVersion":20,"showRowPaths":false}"#.write(to: legacyFile, atomically: true, encoding: .utf8)
        let legacyStore = PreferencesStore(fileName: "legacy.json", directory: dir)
        XCTAssertTrue(legacyStore.preferences.useNativeAppKitList)
        XCTAssertFalse(legacyStore.preferences.showRowPaths)

        // 2. Guardar false -> recargar -> false; guardar true -> recargar -> true
        legacyStore.update { $0.useNativeAppKitList = false }
        let reloadedFalse = PreferencesStore(fileName: "legacy.json", directory: dir)
        XCTAssertFalse(reloadedFalse.preferences.useNativeAppKitList)

        reloadedFalse.update { $0.useNativeAppKitList = true }
        let reloadedTrue = PreferencesStore(fileName: "legacy.json", directory: dir)
        XCTAssertTrue(reloadedTrue.preferences.useNativeAppKitList)
    }

    func testBatchRenameRegexCaptureGroupsCaseChangeAndExistingDiskCollision() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("FindaroBatchTest_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let img = dir.appendingPathComponent("IMG_0042.JPG")
        let existing = dir.appendingPathComponent("Foto_0042.JPG")
        let lowerSrc = dir.appendingPathComponent("draft note.txt")
        try Data().write(to: img)
        try Data().write(to: existing)
        try Data().write(to: lowerSrc)

        let engine = BatchRenameEngine()

        // 1. Regex con grupo de captura ($1) que colisiona con un archivo existente en disco
        let collisionItems = engine.preview(
            urls: [img],
            rules: [.regexReplace(pattern: "^IMG_(\\d+)$", template: "Foto_$1")],
            fileManager: fm
        )
        XCTAssertEqual(collisionItems.count, 1)
        XCTAssertEqual(collisionItems[0].proposedName, "Foto_0042.JPG")
        XCTAssertEqual(collisionItems[0].conflict, .alreadyExistsOnDisk)

        // 2. Regex + cambio de capitalización sin colisión
        let cleanRegex = engine.preview(
            urls: [img],
            rules: [
                .regexReplace(pattern: "^IMG_(\\d+)$", template: "shot_$1"),
                .changeCase(.uppercase)
            ],
            fileManager: fm
        )
        XCTAssertEqual(cleanRegex[0].proposedName, "SHOT_0042.JPG")
        XCTAssertNil(cleanRegex[0].conflict)

        let titleItems = engine.preview(urls: [lowerSrc], rules: [.changeCase(.titleCase)], fileManager: fm)
        XCTAssertEqual(titleItems[0].proposedName, "Draft Note.txt")
        XCTAssertNil(titleItems[0].conflict)
    }

    func testPathResolverHandlesTildeFileParentAndHiddenAutocomplete() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("FindaroPathHiddenTest_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let hiddenDir = base.appendingPathComponent(".config", isDirectory: true)
        let visibleDir = base.appendingPathComponent("docs", isDirectory: true)
        let sampleFile = visibleDir.appendingPathComponent("manual.pdf")
        try fm.createDirectory(at: hiddenDir, withIntermediateDirectories: false)
        try fm.createDirectory(at: visibleDir, withIntermediateDirectories: false)
        try Data().write(to: sampleFile)

        let resolver = PathBarResolver()

        // 1. Tilde (~)
        let homeResult = resolver.resolve(input: "~", fileManager: fm)
        XCTAssertEqual(homeResult, .directory(fm.homeDirectoryForCurrentUser.standardizedFileURL))

        // 2. Archivo -> devuelve .fileParent(directory:targetFile:)
        let fileResult = resolver.resolve(input: sampleFile.path, fileManager: fm)
        XCTAssertEqual(
            fileResult,
            .fileParent(directory: visibleDir.standardizedFileURL, targetFile: sampleFile.standardizedFileURL)
        )

        // 3. Carpetas ocultas solo aparecen si el prefijo comienza con "."
        let withoutDot = resolver.autocompleteDirectories(for: base.path + "/", fileManager: fm)
        XCTAssertEqual(withoutDot.map(\.lastPathComponent), ["docs"])

        let withDot = resolver.autocompleteDirectories(for: base.appendingPathComponent(".c").path, fileManager: fm)
        XCTAssertEqual(withDot.map(\.lastPathComponent), [".config"])
    }
}

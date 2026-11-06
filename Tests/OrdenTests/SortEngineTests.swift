import XCTest
import OrdenCore

final class SortEngineTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testFoldersAlwaysFirstRegardlessOfSortKey() {
        let files = [
            entry("z.txt", isDir: false, modified: Date()),
            entry("a", isDir: true, modified: Date().addingTimeInterval(-day)),
            entry("m.mov", isDir: false, modified: Date().addingTimeInterval(day))
        ]
        let rule = SortRule(keys: [.dateModified(ascending: false)], foldersFirst: true)
        let sorted = SortEngine.sort(files, by: rule)
        XCTAssertTrue(sorted[0].isDirectory)
        XCTAssertEqual(sorted[0].name, "a")
        XCTAssertEqual(sorted[1].name, "m.mov")
    }

    func testNaturalNameOrder() {
        let files = [
            entry("file10.txt"),
            entry("file2.txt"),
            entry("file1.txt")
        ]
        let sorted = SortEngine.sort(files, by: .default)
        XCTAssertEqual(sorted.map(\.name), ["file1.txt", "file2.txt", "file10.txt"])
    }

    func testMultiKeyKindThenName() {
        let files = [
            entry("b.pdf", kind: "PDF"),
            entry("a.pdf", kind: "PDF"),
            entry("z.txt", kind: "Texto"),
            entry("m", isDir: true, kind: "Carpeta")
        ]
        let rule = SortRule(
            keys: [.kind(ascending: true), .name(ascending: true)],
            foldersFirst: true
        )
        let sorted = SortEngine.sort(files, by: rule)
        XCTAssertEqual(sorted.map(\.name), ["m", "a.pdf", "b.pdf", "z.txt"])
    }

    func testSummarySpanishIsReadable() {
        let rule = SortRule(
            keys: [.name(ascending: true)],
            foldersFirst: true
        )
        XCTAssertTrue(rule.summarySpanish.contains("Carpetas arriba"))
        XCTAssertTrue(rule.summarySpanish.contains("Nombre A→Z"))
        XCTAssertTrue(rule.summarySpanish.contains("números naturales"))
    }

    func testDateAddedDescending() {
        let older = Date().addingTimeInterval(-day * 3)
        let newer = Date()
        let files = [
            entry("old.zip", added: older),
            entry("new.zip", added: newer)
        ]
        let rule = SortRule(keys: [.dateAdded(ascending: false)], foldersFirst: true)
        let sorted = SortEngine.sort(files, by: rule)
        XCTAssertEqual(sorted.map(\.name), ["new.zip", "old.zip"])
    }

    func testDownloadsSmartFoldersByNameFilesByDate() {
        let older = Date().addingTimeInterval(-day * 3)
        let newer = Date()
        let files = [
            entry("05_Multimedia", isDir: true, added: newer),
            entry("01_Trading", isDir: true, added: older),
            entry("old.zip", added: older),
            entry("new.zip", added: newer),
            entry("davitor", isDir: true, added: newer.addingTimeInterval(day))
        ]
        let sorted = SortEngine.sort(files, by: .downloads)
        XCTAssertEqual(
            sorted.map(\.name),
            ["01_Trading", "05_Multimedia", "davitor", "new.zip", "old.zip"]
        )
        XCTAssertTrue(SortRule.downloads.summarySpanish.contains("carpetas"))
        XCTAssertTrue(SortRule.downloads.summarySpanish.contains("archivos"))
    }

    private func entry(
        _ name: String,
        isDir: Bool = false,
        kind: String = "Documento",
        modified: Date = Date(),
        added: Date = Date()
    ) -> FileEntry {
        FileEntry(
            path: "/tmp/\(name)",
            name: name,
            isDirectory: isDir,
            size: 10,
            dateModified: modified,
            dateCreated: modified,
            dateAdded: added,
            kind: kind
        )
    }
}

import XCTest
import OrdenCore

final class FileCategoryTests: XCTestCase {
    func testVideosShareCategory() {
        XCTAssertEqual(FileCategory.classify(fileName: "a.mp4", isDirectory: false), .video)
        XCTAssertEqual(FileCategory.classify(fileName: "b.MOV", isDirectory: false), .video)
        XCTAssertEqual(FileCategory.classify(fileName: "c.mkv", isDirectory: false), .video)
        XCTAssertEqual(FileCategory.video.symbolName, "film")
    }

    func testOfficeTypes() {
        XCTAssertEqual(FileCategory.classify(fileName: "presupuesto.xlsx", isDirectory: false), .excel)
        XCTAssertEqual(FileCategory.classify(fileName: "carta.docx", isDirectory: false), .word)
        XCTAssertEqual(FileCategory.classify(fileName: "pitch.pptx", isDirectory: false), .powerpoint)
        XCTAssertEqual(FileCategory.classify(fileName: "manual.pdf", isDirectory: false), .pdf)
    }

    func testSortByCategoryGroupsVideosThenDocs() {
        let entries = [
            FileEntry(path: "/t/z.txt", name: "z.txt", isDirectory: false, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "Texto"),
            FileEntry(path: "/t/a.mp4", name: "a.mp4", isDirectory: false, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "Vídeo"),
            FileEntry(path: "/t/b.xlsx", name: "b.xlsx", isDirectory: false, size: 1,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "Excel"),
            FileEntry(path: "/t/carpeta", name: "carpeta", isDirectory: true, size: 0,
                      dateModified: .now, dateCreated: .now, dateAdded: .now, kind: "Carpeta")
        ]
        let sorted = SortEngine.sort(entries, by: .byType)
        XCTAssertEqual(sorted.map(\.name), ["carpeta", "a.mp4", "b.xlsx", "z.txt"])
    }
}

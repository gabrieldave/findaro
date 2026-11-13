import XCTest
@testable import OrdenCore

final class PathFormatterTests: XCTestCase {
    func testPosixLinesFormatting() {
        let paths = ["/Users/davidai/Downloads/file1.pdf", "/Users/davidai/Documents/doc2.txt"]
        let formatted = PathFormatter.posixLines(for: paths)
        XCTAssertEqual(formatted, "/Users/davidai/Downloads/file1.pdf\n/Users/davidai/Documents/doc2.txt")
    }

    func testShellEscapeSimplePaths() {
        let path = "/Users/davidai/Downloads/simple_file.txt"
        let escaped = PathFormatter.shellEscape(path)
        XCTAssertEqual(escaped, path)
    }

    func testShellEscapePathsWithSpacesAndQuotes() {
        let path = "/Users/davidai/My Documents/Dave's Work/Report.pdf"
        let escaped = PathFormatter.shellEscape(path)
        XCTAssertEqual(escaped, "'/Users/davidai/My Documents/Dave'\\''s Work/Report.pdf'")
    }

    func testShellEscapedMultiplePaths() {
        let paths = [
            "/Users/davidai/file1.txt",
            "/Users/davidai/Folder with space/file2.txt"
        ]
        let escaped = PathFormatter.shellEscaped(for: paths)
        XCTAssertEqual(escaped, "/Users/davidai/file1.txt '/Users/davidai/Folder with space/file2.txt'")
    }

    func testEmptyPathEscape() {
        XCTAssertEqual(PathFormatter.shellEscape(""), "''")
    }
}

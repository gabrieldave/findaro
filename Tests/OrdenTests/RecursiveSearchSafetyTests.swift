import XCTest
import OrdenCore
import Foundation
import CoreGraphics
import CoreText
import ImageIO

final class RecursiveSearchSafetyTests: XCTestCase {
    func testSearchDoesNotFollowSymlinkOutsideRoot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-search-\(UUID().uuidString)", isDirectory: true)
        let inside = root.appendingPathComponent("inside", isDirectory: true)
        let outside = root.appendingPathComponent("inside-evil", isDirectory: true)
        try fm.createDirectory(at: inside, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "needle".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: inside.appendingPathComponent("escape"), withDestinationURL: outside)

        var hits: [SearchHit] = []
        RecursiveSearch.run(
            query: .init(text: "needle", root: inside.path, searchContent: true),
            isCancelled: { false },
            onProgress: { _ in },
            onHit: { hits.append($0) }
        )
        XCTAssertTrue(hits.isEmpty)
    }

    func testSearchFindsTextInsidePDF() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-pdf-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let pdfPath = root.appendingPathComponent("trading_book.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 500, height: 500)
        if let context = CGContext(pdfPath as CFURL, mediaBox: &mediaBox, nil) {
            context.beginPage(mediaBox: &mediaBox)
            let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
            let attrStr = CFAttributedStringCreate(nil, "Secret trading chapter about gold and risk." as CFString, [kCTFontAttributeName: font] as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attrStr)
            context.textPosition = CGPoint(x: 50, y: 400)
            CTLineDraw(line, context)
            context.endPage()
            context.closePDF()

            var hits: [SearchHit] = []
            RecursiveSearch.run(
                query: .init(text: "trading", root: root.path, searchContent: true),
                isCancelled: { false },
                onProgress: { _ in },
                onHit: { hits.append($0) }
            )
            XCTAssertEqual(hits.count, 1)
            XCTAssertEqual(hits.first?.name, "trading_book.pdf")
        }
    }

    func testSearchFindsTextInsideImageOCR() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("orden-ocr-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let imgPath = root.appendingPathComponent("daveax_screenshot.png")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let width = 400
        let height = 200
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            XCTFail("Could not create CGContext")
            return
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 36, nil)
        let attrStr = CFAttributedStringCreate(nil, "DAVEAX" as CFString, [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1)] as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        ctx.textPosition = CGPoint(x: 50, y: 80)
        CTLineDraw(line, ctx)

        guard let cgImg = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(imgPath as CFURL, "public.png" as CFString, 1, nil) else {
            XCTFail("Could not create Image Destination")
            return
        }
        CGImageDestinationAddImage(dest, cgImg, nil)
        guard CGImageDestinationFinalize(dest) else {
            XCTFail("Could not finalize PNG image")
            return
        }

        var hits: [SearchHit] = []
        RecursiveSearch.run(
            query: .init(text: "DAVEAX", root: root.path, searchContent: true),
            isCancelled: { false },
            onProgress: { _ in },
            onHit: { hits.append($0) }
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.name, "daveax_screenshot.png")
    }
}

import XCTest
@testable import OrdenCore

final class PressDragSelectLogicTests: XCTestCase {
    func testNameHitDragsFile() {
        let action = PressDragSelectLogic.startAction(
            hitOnName: true,
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: ["/tmp/other.zip"],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: []
        )
        XCTAssertEqual(action, .beginFileDrag(paths: ["/tmp/a.pdf"], selectOnlyID: "a"))
    }

    func testSelectedNameDragsWholeSelection() {
        let action = PressDragSelectLogic.startAction(
            hitOnName: true,
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: true,
            selectedPaths: ["/tmp/a.pdf", "/tmp/b.pdf"],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: []
        )
        XCTAssertEqual(action, .beginFileDrag(paths: ["/tmp/a.pdf", "/tmp/b.pdf"], selectOnlyID: nil))
    }

    func testEmptySpaceStartsMarquee() {
        let action = PressDragSelectLogic.startAction(
            hitOnName: false,
            hitID: nil,
            hitPath: nil,
            hitIsSelected: false,
            selectedPaths: [],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: []
        )
        XCTAssertEqual(action, .beginMarquee(additive: false))
    }

    func testRowWithoutNameIsMarquee() {
        // Clic en fecha/tamaño (hay fila) pero fuera del nombre → marquesina Finder.
        let action = PressDragSelectLogic.startAction(
            hitOnName: false,
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: true,
            selectedPaths: ["/tmp/a.pdf"],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: []
        )
        XCTAssertEqual(action, .beginMarquee(additive: false))
    }

    func testShiftAlwaysAdditiveMarquee() {
        let action = PressDragSelectLogic.startAction(
            hitOnName: true,
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: ["/tmp/b.pdf"],
            commandHeld: false,
            shiftHeld: true,
            hasArmedFileDrag: false,
            armedPaths: []
        )
        XCTAssertEqual(action, .beginMarquee(additive: true))
    }

    func testCommandWithoutArmIsIgnored() {
        let action = PressDragSelectLogic.startAction(
            hitOnName: true,
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: [],
            commandHeld: true,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: []
        )
        XCTAssertEqual(action, .ignore)
    }
}

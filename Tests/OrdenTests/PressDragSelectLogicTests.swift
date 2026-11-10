import XCTest
@testable import OrdenCore

final class PressDragSelectLogicTests: XCTestCase {
    func testUnselectedFileDragsImmediately() {
        let action = PressDragSelectLogic.startAction(
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: ["/tmp/other.zip"],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .beginFileDrag(paths: ["/tmp/a.pdf"], selectOnlyID: "a"))
    }

    func testSelectedFileDragsWholeSelection() {
        let action = PressDragSelectLogic.startAction(
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: true,
            selectedPaths: ["/tmp/a.pdf", "/tmp/b.pdf"],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .beginFileDrag(paths: ["/tmp/a.pdf", "/tmp/b.pdf"], selectOnlyID: nil))
    }

    func testEmptySpaceStartsMarquee() {
        let action = PressDragSelectLogic.startAction(
            hitID: nil,
            hitPath: nil,
            hitIsSelected: false,
            selectedPaths: [],
            commandHeld: false,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .beginMarquee(additive: false))
    }

    func testShiftOnUnselectedKeepsAdditiveMarquee() {
        let action = PressDragSelectLogic.startAction(
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: ["/tmp/b.pdf"],
            commandHeld: false,
            shiftHeld: true,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .beginMarquee(additive: true))
    }

    func testCommandWithoutArmIsIgnored() {
        let action = PressDragSelectLogic.startAction(
            hitID: "a",
            hitPath: "/tmp/a.pdf",
            hitIsSelected: false,
            selectedPaths: [],
            commandHeld: true,
            shiftHeld: false,
            hasArmedFileDrag: false,
            armedPaths: [],
            isArming: false
        )
        XCTAssertEqual(action, .ignore)
    }
}

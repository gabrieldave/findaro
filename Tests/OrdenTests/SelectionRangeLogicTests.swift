import XCTest
@testable import OrdenCore

final class SelectionRangeLogicTests: XCTestCase {
    let sampleIDs = ["file1", "file2", "file3", "file4", "file5"]

    func testComputeRangeForward() {
        let (range, anchor) = SelectionRangeLogic.computeRange(ids: sampleIDs, anchor: "file2", target: "file4")
        XCTAssertEqual(range, Set(["file2", "file3", "file4"]))
        XCTAssertEqual(anchor, "file2")
    }

    func testComputeRangeBackward() {
        let (range, anchor) = SelectionRangeLogic.computeRange(ids: sampleIDs, anchor: "file4", target: "file2")
        XCTAssertEqual(range, Set(["file2", "file3", "file4"]))
        XCTAssertEqual(anchor, "file4")
    }

    func testComputeRangeWithoutExistingAnchorUsesTarget() {
        let (range, anchor) = SelectionRangeLogic.computeRange(ids: sampleIDs, anchor: nil, target: "file3")
        XCTAssertEqual(range, Set(["file3"]))
        XCTAssertEqual(anchor, "file3")
    }

    func testToggleAddsItemIfNotPresent() {
        let initial: Set<String> = ["file1", "file3"]
        let result = SelectionRangeLogic.toggle(selectedIDs: initial, id: "file2")
        XCTAssertEqual(result, Set(["file1", "file2", "file3"]))
    }

    func testToggleRemovesItemIfPresent() {
        let initial: Set<String> = ["file1", "file2", "file3"]
        let result = SelectionRangeLogic.toggle(selectedIDs: initial, id: "file2")
        XCTAssertEqual(result, Set(["file1", "file3"]))
    }

    func testNextKeyboardSelectionDownSingle() {
        let result = SelectionRangeLogic.nextKeyboardSelection(
            ids: sampleIDs,
            currentFocus: "file2",
            currentAnchor: "file2",
            selectedIDs: ["file2"],
            delta: 1,
            extending: false
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newSelected, ["file3"])
        XCTAssertEqual(result?.newAnchor, "file3")
        XCTAssertEqual(result?.newFocus, "file3")
    }

    func testNextKeyboardSelectionDownExtendingMaintainsAnchor() {
        let result = SelectionRangeLogic.nextKeyboardSelection(
            ids: sampleIDs,
            currentFocus: "file2",
            currentAnchor: "file2",
            selectedIDs: ["file2"],
            delta: 1,
            extending: true
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newSelected, ["file2", "file3"])
        XCTAssertEqual(result?.newAnchor, "file2")
        XCTAssertEqual(result?.newFocus, "file3")

        // Extend one more step down
        let result2 = SelectionRangeLogic.nextKeyboardSelection(
            ids: sampleIDs,
            currentFocus: result!.newFocus,
            currentAnchor: result!.newAnchor,
            selectedIDs: result!.newSelected,
            delta: 1,
            extending: true
        )
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.newSelected, ["file2", "file3", "file4"])
        XCTAssertEqual(result2?.newAnchor, "file2")
        XCTAssertEqual(result2?.newFocus, "file4")
    }

    func testNextKeyboardSelectionWhenEmptyInitializesFirst() {
        let result = SelectionRangeLogic.nextKeyboardSelection(
            ids: sampleIDs,
            currentFocus: nil,
            currentAnchor: nil,
            selectedIDs: [],
            delta: 1,
            extending: false
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newSelected, ["file1"])
        XCTAssertEqual(result?.newAnchor, "file1")
        XCTAssertEqual(result?.newFocus, "file1")
    }

    func testNextKeyboardSelectionUpExtendingMaintainsAnchor() {
        let result = SelectionRangeLogic.nextKeyboardSelection(
            ids: sampleIDs,
            currentFocus: "file3",
            currentAnchor: "file3",
            selectedIDs: ["file3"],
            delta: -1,
            extending: true
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newSelected, ["file2", "file3"])
        XCTAssertEqual(result?.newAnchor, "file3")
        XCTAssertEqual(result?.newFocus, "file2")

        let result2 = SelectionRangeLogic.nextKeyboardSelection(
            ids: sampleIDs,
            currentFocus: result!.newFocus,
            currentAnchor: result!.newAnchor,
            selectedIDs: result!.newSelected,
            delta: -1,
            extending: true
        )
        XCTAssertNotNil(result2)
        XCTAssertEqual(result2?.newSelected, ["file1", "file2", "file3"])
        XCTAssertEqual(result2?.newAnchor, "file3")
        XCTAssertEqual(result2?.newFocus, "file1")
    }

    func testNextKeyboardSelectionShrinkBackToAnchor() {
        // Starts with file2, file3, file4 (anchor file2, focus file4)
        let result = SelectionRangeLogic.nextKeyboardSelection(
            ids: sampleIDs,
            currentFocus: "file4",
            currentAnchor: "file2",
            selectedIDs: ["file2", "file3", "file4"],
            delta: -1,
            extending: true
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.newSelected, ["file2", "file3"])
        XCTAssertEqual(result?.newAnchor, "file2")
        XCTAssertEqual(result?.newFocus, "file3")
    }

    func testMultipleCommandClicksToggleIndependently() {
        var selected: Set<String> = ["file1"]
        // User ⌘+clicks file3
        selected = SelectionRangeLogic.toggle(selectedIDs: selected, id: "file3")
        XCTAssertEqual(selected, ["file1", "file3"])
        // User ⌘+clicks file5
        selected = SelectionRangeLogic.toggle(selectedIDs: selected, id: "file5")
        XCTAssertEqual(selected, ["file1", "file3", "file5"])
        // User ⌘+clicks file3 again (uncheck)
        selected = SelectionRangeLogic.toggle(selectedIDs: selected, id: "file3")
        XCTAssertEqual(selected, ["file1", "file5"])
    }
}

import XCTest
@testable import OrdenCore

final class HardwareIdentityTests: XCTestCase {
    func testChipModelIsNonEmptyAndNotPlaceholder() {
        let chip = HardwareIdentity.chipModel
        XCTAssertFalse(chip.isEmpty)
        XCTAssertNotEqual(chip, "UNKNOWN")
        XCTAssertNotEqual(chip, "GENERIC_CHIP")
        // On modern macOS machines running this, it should identify Apple Silicon (e.g., Apple M4) or Intel
        XCTAssertTrue(chip.contains("Apple") || chip.contains("Intel") || chip.contains("Silicon"))
    }

    func testMacOSVersionStringIsFormattedCorrectly() {
        let version = HardwareIdentity.macOSVersionString
        XCTAssertFalse(version.isEmpty)
        let parts = version.split(separator: ".")
        XCTAssertGreaterThanOrEqual(parts.count, 2)
        XCTAssertNotNil(Int(parts[0]))
    }

    func testModelIdentifierIsNonEmpty() {
        let model = HardwareIdentity.modelIdentifier
        XCTAssertFalse(model.isEmpty)
        XCTAssertTrue(model.hasPrefix("Mac"))
    }

    func testPhysicalMemoryIsGreaterThanZero() {
        let ram = HardwareIdentity.physicalMemoryGigabytes
        XCTAssertGreaterThan(ram, 0)
    }
}

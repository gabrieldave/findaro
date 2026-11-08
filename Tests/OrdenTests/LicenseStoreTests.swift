import XCTest
@testable import OrdenCore

final class LicenseStoreTests: XCTestCase {
    var tempDefaults: UserDefaults!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.findaro.license.\(UUID().uuidString)"
        tempDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        tempDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func testHardwareIDIsNotEmpty() {
        let id = HardwareID.current()
        XCTAssertFalse(id.isEmpty)
    }

    @MainActor
    func testInitialStateIsTrialWithDaysRemaining() {
        let store = LicenseStore(defaults: tempDefaults)
        switch store.state {
        case .trial(let days, _):
            XCTAssertGreaterThanOrEqual(days, 1)
            XCTAssertLessThanOrEqual(days, 5)
        default:
            XCTFail("Expected trial state on clean launch, got: \(store.state)")
        }
    }

    @MainActor
    func testTrialExpiredWhenTrialDateIsOlderThan5Days() {
        let pastDate = Date().addingTimeInterval(-6 * 24 * 60 * 60)
        tempDefaults.set(pastDate, forKey: "findaro.trial.start")

        let store = LicenseStore(defaults: tempDefaults)
        XCTAssertEqual(store.state, .trialExpired)
        XCTAssertFalse(store.state.isUsable)
    }

    @MainActor
    func testProActiveStateWhenValidTokenExists() {
        // Mock payload {"v":1,"plan":"pro","tier":"family","key":"FINDARO-TEST-1234","seats":5}
        let json = #"{"v":1,"plan":"pro","tier":"family","key":"FINDARO-TEST-1234","seats":5}"#
        let base64 = Data(json.utf8).base64EncodedString()
        let token = "F1.\(base64).mockSignature"

        tempDefaults.set(token, forKey: "findaro.license.token")
        tempDefaults.set("FINDARO-TEST-1234", forKey: "findaro.license.key")

        let store = LicenseStore(defaults: tempDefaults)
        switch store.state {
        case .proActive(let key, let tier, let seats, _):
            XCTAssertEqual(key, "FINDARO-TEST-1234")
            XCTAssertEqual(tier, "family")
            XCTAssertEqual(seats, 5)
            XCTAssertTrue(store.state.isPro)
            XCTAssertTrue(store.state.isUsable)
        default:
            XCTFail("Expected proActive state, got: \(store.state)")
        }
    }
}

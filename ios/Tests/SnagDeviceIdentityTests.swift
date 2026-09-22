import XCTest
@testable import Snag

final class SnagDeviceIdentityTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.snag.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testGeneratedIdentifierIsStoredOnFirstUse() {
        XCTAssertNil(defaults.string(forKey: "com.snag.deviceId"))
        let generated = SnagUtility.persistedDeviceId(defaults: defaults)
        XCTAssertFalse(generated.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "com.snag.deviceId"), generated)
    }

    func testIdentifierIsStableAcrossCalls() {
        let first = SnagUtility.persistedDeviceId(defaults: defaults)
        let second = SnagUtility.persistedDeviceId(defaults: defaults)
        XCTAssertEqual(first, second)
    }

    func testStoredIdentifierIsReused() {
        defaults.set("existing-id", forKey: "com.snag.deviceId")
        XCTAssertEqual(SnagUtility.persistedDeviceId(defaults: defaults), "existing-id")
    }

    func testEmptyStoredIdentifierIsReplaced() {
        defaults.set("", forKey: "com.snag.deviceId")
        let generated = SnagUtility.persistedDeviceId(defaults: defaults)
        XCTAssertFalse(generated.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "com.snag.deviceId"), generated)
    }

    func testTwoInstallsDoNotShareAGeneratedIdentifier() {
        let otherSuite = "com.snag.tests.\(UUID().uuidString)"
        let other = UserDefaults(suiteName: otherSuite)!
        defer { other.removePersistentDomain(forName: otherSuite) }
        XCTAssertNotEqual(SnagUtility.persistedDeviceId(defaults: defaults),
                          SnagUtility.persistedDeviceId(defaults: other))
    }
}

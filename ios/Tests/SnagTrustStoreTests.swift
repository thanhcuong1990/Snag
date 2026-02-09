import XCTest
@testable import Snag

final class SnagTrustStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SnagTrustStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SnagTrustStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = SnagTrustStore(defaults: defaults)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testTOFUThenRejectMismatch() {
        let first = store.verifyOrTrust(serverKey: "bonjour|demo", fingerprint: "aaa")
        XCTAssertEqual(first, .trusted)

        let second = store.verifyOrTrust(serverKey: "bonjour|demo", fingerprint: "aaa")
        XCTAssertEqual(second, .trusted)

        let mismatch = store.verifyOrTrust(serverKey: "bonjour|demo", fingerprint: "bbb")
        XCTAssertEqual(
            mismatch,
            .mismatch(expectedFingerprint: "aaa", actualFingerprint: "bbb")
        )

        let metrics = store.metricsSnapshot()
        XCTAssertEqual(metrics.trustedServerCount, 1)
        XCTAssertEqual(metrics.mismatchCount, 1)
    }
}

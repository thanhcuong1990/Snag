import XCTest
@testable import Snag

final class FixtureCaptureFilterTests: XCTestCase {

    private let analytics = "https://api.communa.sg/analytics/tracking/events"
    private let posts = "https://api.communa.sg/content/api/v4/posts"
    private let wishlist = "https://api.communa.sg/hv_shop/api/v1/wishlist"

    private func matches(_ url: String, _ filter: String) -> Bool {
        FixtureCaptureService.matches(url: url, hostFilter: filter)
    }

    func testEmptyFilterRecordsEverything() {
        XCTAssertTrue(matches(analytics, ""))
        XCTAssertTrue(matches(posts, ""))
    }

    func testWhitespaceOnlyFilterRecordsEverything() {
        XCTAssertTrue(matches(posts, "   "))
    }

    func testHostFilterKeepsEveryRequestOnThatHost() {
        XCTAssertTrue(matches(analytics, "communa.sg"))
        XCTAssertTrue(matches(posts, "communa.sg"))
        XCTAssertTrue(matches(wishlist, "communa.sg"))
    }

    func testFilterMatchesAcrossHostAndPath() {
        XCTAssertTrue(matches(analytics, "communa.sg/analytics"))
        XCTAssertFalse(matches(posts, "communa.sg/analytics"))
        XCTAssertFalse(matches(wishlist, "communa.sg/analytics"))
    }

    func testFilterIgnoresCaseAndSurroundingWhitespace() {
        XCTAssertTrue(matches(analytics, "  COMMUNA.sg/Analytics  "))
        XCTAssertFalse(matches(posts, "  COMMUNA.sg/Analytics  "))
    }
}

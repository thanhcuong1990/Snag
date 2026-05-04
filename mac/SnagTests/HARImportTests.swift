import XCTest
@testable import Snag

@MainActor
final class HARImportTests: XCTestCase {

    private func parse(_ json: String) throws -> ImportableBatch {
        try HARImporter.parse(.text(json), options: CurlImportOptions())
    }

    // MARK: - canHandle

    func testCanHandleRecognizesHARShape() {
        let har = #"{"log":{"version":"1.2","entries":[]}}"#
        XCTAssertTrue(HARImporter.canHandle(.text(har)))
    }

    func testCanHandleRejectsPostman() {
        let pm = #"{"info":{"name":"x","schema":"v2.1"},"item":[]}"#
        XCTAssertFalse(HARImporter.canHandle(.text(pm)))
    }

    // MARK: - Plan §7: HAR with 2 entries → 2 drafts

    func testTwoEntriesProduceTwoRequests() throws {
        let har = """
        {
          "log": {
            "version": "1.2",
            "entries": [
              {
                "startedDateTime": "2024-01-01T00:00:00Z",
                "request": {
                  "method": "GET",
                  "url": "https://x.test/a?q=1",
                  "headers": [
                    { "name": "Accept", "value": "application/json" },
                    { "name": ":authority", "value": "x.test" }
                  ],
                  "queryString": [{ "name": "q", "value": "1" }],
                  "cookies": [],
                  "headersSize": -1, "bodySize": -1
                }
              },
              {
                "startedDateTime": "2024-01-01T00:00:01Z",
                "request": {
                  "method": "POST",
                  "url": "https://x.test/b",
                  "headers": [{ "name": "Content-Type", "value": "application/json" }],
                  "queryString": [],
                  "cookies": [],
                  "headersSize": -1, "bodySize": -1,
                  "postData": { "mimeType": "application/json", "text": "{\\"k\\":1}" }
                }
              }
            ]
          }
        }
        """
        let batch = try parse(har)
        XCTAssertEqual(batch.requests.count, 2)
        XCTAssertNil(batch.folders, "HAR is flat")

        let a = batch.requests[0]
        XCTAssertEqual(a.draftData.method, "GET")
        // HTTP/2 pseudo-header (`:authority`) should have been dropped.
        XCTAssertFalse(a.draftData.headers.contains { $0.key.hasPrefix(":") })
        XCTAssertEqual(a.draftData.queryParams.first?.key, "q")

        let b = batch.requests[1]
        XCTAssertEqual(b.draftData.method, "POST")
        XCTAssertEqual(b.draftData.bodyEncoding, .json)
        XCTAssertNotNil(b.draftData.bodyBase64)
    }

    // MARK: - HAR cookies → Cookie header

    func testHARCookiesAreFoldedIntoCookieHeader() throws {
        let har = """
        {
          "log": {
            "version": "1.2",
            "entries": [{
              "request": {
                "method": "GET",
                "url": "https://x.test/",
                "headers": [],
                "queryString": [],
                "cookies": [
                  { "name": "a", "value": "1" },
                  { "name": "b", "value": "2" }
                ],
                "headersSize": -1, "bodySize": -1
              }
            }]
          }
        }
        """
        let batch = try parse(har)
        let req = batch.requests[0]
        let cookie = req.draftData.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }
        XCTAssertNotNil(cookie)
        XCTAssertEqual(cookie?.value, "a=1; b=2")
    }

    // MARK: - Empty HAR throws

    func testEmptyEntriesThrows() {
        let har = #"{"log":{"version":"1.2","entries":[]}}"#
        XCTAssertThrowsError(try parse(har)) { e in
            XCTAssertTrue(e is ImportError)
        }
    }
}

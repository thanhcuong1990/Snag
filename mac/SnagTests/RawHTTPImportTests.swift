import XCTest
@testable import Snag

@MainActor
final class RawHTTPImportTests: XCTestCase {

    func testCanHandleRequestLine() {
        XCTAssertTrue(RawHTTPImporter.canHandle(.text("GET /a HTTP/1.1\r\nHost: x.test\r\n\r\n")))
        XCTAssertTrue(RawHTTPImporter.canHandle(.text("POST /b HTTP/1.0\nHost: y.test\n\n")))
    }

    func testCanHandleRejectsCurl() {
        XCTAssertFalse(RawHTTPImporter.canHandle(.text("curl https://x.test/")))
    }

    func testParseGetUsesHostHeader() throws {
        let raw = "GET /items?q=1 HTTP/1.1\r\nHost: x.test\r\nAccept: application/json\r\n\r\n"
        let batch = try RawHTTPImporter.parse(.text(raw), options: CurlImportOptions())
        XCTAssertEqual(batch.requests.count, 1)
        let r = batch.requests[0].draftData
        XCTAssertEqual(r.method, "GET")
        XCTAssertTrue(r.url.hasPrefix("https://x.test/items"))
        XCTAssertEqual(r.queryParams.first?.key, "q")
    }

    func testParsePostJSONBody() throws {
        let raw = """
        POST /items HTTP/1.1\r
        Host: x.test\r
        Content-Type: application/json\r
        \r
        {"k":"v"}
        """
        let batch = try RawHTTPImporter.parse(.text(raw), options: CurlImportOptions())
        let r = batch.requests[0].draftData
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.bodyEncoding, .json)
        XCTAssertNotNil(r.bodyBase64)
        let decoded = Data(base64Encoded: r.bodyBase64 ?? "").flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(decoded, #"{"k":"v"}"#)
    }

    func testParseLFOnlyLineEndings() throws {
        let raw = "DELETE /items/1 HTTP/1.1\nHost: x.test\nAuthorization: Bearer abc\n\n"
        let batch = try RawHTTPImporter.parse(.text(raw), options: CurlImportOptions())
        let r = batch.requests[0].draftData
        XCTAssertEqual(r.method, "DELETE")
        XCTAssertTrue(r.headers.contains { $0.key == "Authorization" && $0.value == "Bearer abc" })
    }

    func testRequestImportersAutoDetectsRawHTTP() {
        let raw = "GET /a HTTP/1.1\r\nHost: x.test\r\n\r\n"
        XCTAssertEqual(RequestImporters.detect(.text(raw)), .rawHTTP)
    }
}

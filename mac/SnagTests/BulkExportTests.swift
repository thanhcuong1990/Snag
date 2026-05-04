import XCTest
@testable import Snag

@MainActor
final class BulkExportTests: XCTestCase {

    private func sampleGet() -> RequestDraftData {
        RequestDraftData(
            name: "List items",
            url: "https://x.test/items?q=1",
            method: "GET",
            headers: [DraftKeyValue(key: "Accept", value: "application/json")],
            queryParams: [DraftKeyValue(key: "q", value: "1")]
        )
    }

    private func samplePost() -> RequestDraftData {
        RequestDraftData(
            name: "Create item",
            url: "https://x.test/items",
            method: "POST",
            headers: [DraftKeyValue(key: "Content-Type", value: "application/json")],
            bodyBase64: Data(#"{"name":"a"}"#.utf8).base64EncodedString(),
            bodyEncoding: .json
        )
    }

    // MARK: - HAR

    func testHARExportProducesValidJSONWithEntries() throws {
        let har = HARExporter.export([sampleGet(), samplePost()])
        let data = har.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let log = root?["log"] as? [String: Any]
        let entries = log?["entries"] as? [[String: Any]]
        XCTAssertEqual(entries?.count, 2)
        let methods = entries?.compactMap { ($0["request"] as? [String: Any])?["method"] as? String }
        XCTAssertEqual(methods, ["GET", "POST"])
    }

    func testHARRoundTripThroughImporter() throws {
        let original = sampleGet()
        let har = HARExporter.export([original])
        let batch = try HARImporter.parse(.text(har), options: CurlImportOptions())
        XCTAssertEqual(batch.requests.count, 1)
        let r = batch.requests[0].draftData
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.rebuildURL(), original.rebuildURL())
        XCTAssertTrue(r.headers.contains { $0.key.caseInsensitiveCompare("Accept") == .orderedSame &&
                                           $0.value == "application/json" })
    }

    // MARK: - Postman

    func testPostmanExportProducesValidCollectionShape() throws {
        let pm = PostmanCollectionExporter.export([sampleGet(), samplePost()])
        let data = pm.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let info = root?["info"] as? [String: Any]
        XCTAssertNotNil(info?["schema"])
        let items = root?["item"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual((items?[0]["request"] as? [String: Any])?["method"] as? String, "GET")
        XCTAssertEqual((items?[1]["request"] as? [String: Any])?["method"] as? String, "POST")
    }

    func testPostmanRoundTripThroughImporter() throws {
        let original = samplePost()
        let pm = PostmanCollectionExporter.export([original])
        let batch = try PostmanCollectionImporter.parse(.text(pm), options: CurlImportOptions())
        XCTAssertEqual(batch.requests.count, 1)
        let r = batch.requests[0].draftData
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.rebuildURL(), original.rebuildURL())
        XCTAssertEqual(r.bodyEncoding, .json)
    }

    // MARK: - Format gating

    func testCurlFormatRejectsBulkExport() {
        XCTAssertThrowsError(
            try RequestExporters.exportBulk([sampleGet()], as: .curl)
        ) { e in
            XCTAssertTrue(e is ExportError)
        }
    }

    func testHARAndPostmanFormatsAdvertiseBulkSupport() {
        XCTAssertTrue(ExportFormat.har.supportsBulk)
        XCTAssertTrue(ExportFormat.postmanCollection.supportsBulk)
        XCTAssertFalse(ExportFormat.curl.supportsBulk)
    }
}

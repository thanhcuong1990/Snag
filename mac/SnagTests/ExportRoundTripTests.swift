import XCTest
@testable import Snag

@MainActor
final class ExportRoundTripTests: XCTestCase {

    // MARK: - cURL escaping

    func testCurlExportEscapesSingleQuoteInBody() {
        var d = RequestDraftData(url: "https://x.test/", method: "POST")
        d.bodyBase64 = Data(#"{"name":"O'Brien"}"#.utf8).base64EncodedString()
        let out = CurlExporter.export(d)
        XCTAssertTrue(out.contains(#"O'\''Brien"#),
                      "Single quotes in body must be escaped as '\\''")
    }

    func testCurlExportEscapesDoubleQuoteInHeader() {
        var d = RequestDraftData(url: "https://x.test/", method: "GET")
        d.headers = [DraftKeyValue(key: "X-Quote", value: #"a"b"#)]
        let out = CurlExporter.export(d)
        // Headers are wrapped in double quotes, so " becomes \"
        XCTAssertTrue(out.contains(#"-H "X-Quote: a\"b""#))
    }

    func testCurlExportSkipsDisabledHeaders() {
        var d = RequestDraftData(url: "https://x.test/", method: "GET")
        d.headers = [
            DraftKeyValue(key: "Keep", value: "yes"),
            DraftKeyValue(key: "Drop", value: "no", enabled: false),
        ]
        let out = CurlExporter.export(d)
        XCTAssertTrue(out.contains("Keep: yes"))
        XCTAssertFalse(out.contains("Drop"))
    }

    func testCurlExportSkipsContentTypeForMultipart() {
        var d = RequestDraftData(url: "https://x.test/", method: "POST")
        d.bodyEncoding = .multipart
        d.headers = [DraftKeyValue(key: "Content-Type", value: "application/json")]
        d.multipartParts = [DraftMultipartPart(name: "k", kind: .text, textValue: "v")]
        let out = CurlExporter.export(d)
        XCTAssertFalse(out.contains("application/json"),
                      "User Content-Type must be omitted for multipart (curl computes its own)")
        XCTAssertTrue(out.contains("-F 'k=v'"))
    }

    func testCurlExportRebuildsURLFromQueryParams() {
        var d = RequestDraftData(url: "https://x.test/path", method: "GET")
        d.queryParams = [
            DraftKeyValue(key: "a", value: "1"),
            DraftKeyValue(key: "b", value: "2", enabled: false),
            DraftKeyValue(key: "c", value: "3"),
        ]
        let out = CurlExporter.export(d)
        XCTAssertTrue(out.contains("https://x.test/path?a=1&c=3"))
    }

    // MARK: - Round-trip semantic equivalence

    func testRoundTripSimpleGet() throws {
        var d = RequestDraftData(url: "https://x.test/path", method: "GET")
        d.queryParams = [DraftKeyValue(key: "a", value: "1")]
        d.url = d.rebuildURL()

        let cmd = CurlExporter.export(d)
        let parsed = try CurlImporter.parse(cmd).draft

        XCTAssertEqual(parsed.method, d.method)
        XCTAssertEqual(parsed.url, d.url)
        XCTAssertEqual(parsed.queryParams.map { $0.key }, d.queryParams.map { $0.key })
    }

    func testRoundTripPostJson() throws {
        var d = RequestDraftData(url: "https://x.test/api", method: "POST")
        d.headers = [DraftKeyValue(key: "Content-Type", value: "application/json")]
        d.bodyEncoding = .json
        d.bodyBase64 = Data(#"{"a":1,"b":"x"}"#.utf8).base64EncodedString()

        let cmd = CurlExporter.export(d)
        let parsed = try CurlImporter.parse(cmd).draft

        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.bodyEncoding, .json)
        let pBody = Data(base64Encoded: parsed.bodyBase64 ?? "") ?? Data()
        XCTAssertEqual(String(data: pBody, encoding: .utf8), #"{"a":1,"b":"x"}"#)
    }

    func testRoundTripWithSingleQuoteInBody() throws {
        var d = RequestDraftData(url: "https://x.test/", method: "POST")
        d.headers = [DraftKeyValue(key: "Content-Type", value: "application/json")]
        d.bodyEncoding = .json
        d.bodyBase64 = Data(#"{"name":"O'Brien"}"#.utf8).base64EncodedString()

        let cmd = CurlExporter.export(d)
        let parsed = try CurlImporter.parse(cmd).draft
        let pBody = Data(base64Encoded: parsed.bodyBase64 ?? "") ?? Data()
        XCTAssertEqual(String(data: pBody, encoding: .utf8), #"{"name":"O'Brien"}"#)
    }

    func testRoundTripMultipart() throws {
        var d = RequestDraftData(url: "https://x.test/upload", method: "POST")
        d.bodyEncoding = .multipart
        d.multipartParts = [
            DraftMultipartPart(name: "title", kind: .text, textValue: "hi"),
            DraftMultipartPart(name: "file", kind: .file,
                               fileURL: URL(fileURLWithPath: "/tmp/x.png").absoluteString,
                               fileName: "foo.png",
                               contentType: "image/png"),
        ]

        let cmd = CurlExporter.export(d)
        let parsed = try CurlImporter.parse(
            cmd, options: CurlImportOptions(loadLocalFiles: true)
        ).draft

        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.bodyEncoding, .multipart)
        XCTAssertEqual(parsed.multipartParts.count, 2)
        let textP = parsed.multipartParts.first { $0.name == "title" }!
        XCTAssertEqual(textP.textValue, "hi")
        let fileP = parsed.multipartParts.first { $0.name == "file" }!
        XCTAssertEqual(fileP.kind, .file)
        XCTAssertEqual(fileP.fileName, "foo.png")
        XCTAssertEqual(fileP.contentType, "image/png")
        XCTAssertTrue(fileP.fileURL?.contains("/tmp/x.png") ?? false)
    }
}

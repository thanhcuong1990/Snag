import XCTest
@testable import Snag

@MainActor
final class SnippetExporterTests: XCTestCase {

    private func sampleJSON() -> RequestDraftData {
        RequestDraftData(
            url: "https://x.test/items",
            method: "POST",
            headers: [DraftKeyValue(key: "Content-Type", value: "application/json")],
            bodyBase64: Data(#"{"k":"v"}"#.utf8).base64EncodedString(),
            bodyEncoding: .json
        )
    }

    private func sampleMultipart() -> RequestDraftData {
        RequestDraftData(
            url: "https://x.test/upload",
            method: "POST",
            headers: [],
            bodyEncoding: .multipart,
            multipartParts: [
                DraftMultipartPart(name: "name", kind: .text, textValue: "alice"),
                DraftMultipartPart(name: "avatar", kind: .file,
                                   fileURL: "file:///tmp/a.png",
                                   contentType: "image/png")
            ]
        )
    }

    private func sampleGet() -> RequestDraftData {
        RequestDraftData(
            url: "https://x.test/items",
            method: "GET",
            headers: [DraftKeyValue(key: "Accept", value: "application/json")],
            queryParams: [DraftKeyValue(key: "q", value: "1")]
        )
    }

    // MARK: - HTTPie

    func testHTTPieEmitsCommand() {
        let s = HTTPieExporter.export(sampleJSON())
        XCTAssertTrue(s.hasPrefix("http"), "got: \(s)")
        XCTAssertTrue(s.contains("--json"))
        XCTAssertTrue(s.contains("POST"))
        XCTAssertTrue(s.contains("https://x.test/items"))
        XCTAssertTrue(s.contains("Content-Type:application/json"))
    }

    func testHTTPieMultipart() {
        let s = HTTPieExporter.export(sampleMultipart())
        XCTAssertTrue(s.contains("--multipart"))
        XCTAssertTrue(s.contains("name=alice"))
        XCTAssertTrue(s.contains("avatar@/tmp/a.png"))
    }

    // MARK: - Raw HTTP

    func testRawHTTPHasRequestLineAndHostHeader() {
        let s = RawHTTPExporter.export(sampleGet())
        XCTAssertTrue(s.hasPrefix("GET /items?q=1 HTTP/1.1\r\n"))
        XCTAssertTrue(s.contains("Host: x.test"))
        XCTAssertTrue(s.contains("Accept: application/json"))
        XCTAssertTrue(s.contains("\r\n\r\n"))
    }

    func testRawHTTPInjectsHostFromURL() {
        let s = RawHTTPExporter.export(sampleJSON())
        XCTAssertTrue(s.contains("Host: x.test"))
    }

    // MARK: - Python requests

    func testPythonRequestsImportsAndCallsRequest() {
        let s = PythonRequestsExporter.export(sampleJSON())
        XCTAssertTrue(s.contains("import requests"))
        XCTAssertTrue(s.contains("requests.request("))
        XCTAssertTrue(s.contains("method=\"POST\""))
        XCTAssertTrue(s.contains("url=\"https://x.test/items\""))
        XCTAssertTrue(s.contains("json={\"k\":\"v\"}"))
    }

    func testPythonMultipart() {
        let s = PythonRequestsExporter.export(sampleMultipart())
        XCTAssertTrue(s.contains("data="))
        XCTAssertTrue(s.contains("files="))
        XCTAssertTrue(s.contains("\"alice\""))
        XCTAssertTrue(s.contains("open(\"/tmp/a.png\", \"rb\")"))
    }

    // MARK: - JS fetch

    func testJSFetchEmitsAwaitFetchCall() {
        let s = JSFetchExporter.export(sampleJSON())
        XCTAssertTrue(s.contains("await fetch("))
        XCTAssertTrue(s.contains("method: \"POST\""))
        XCTAssertTrue(s.contains("body: JSON.stringify({\"k\":\"v\"})"))
    }

    func testJSFetchMultipartUsesFormData() {
        let s = JSFetchExporter.export(sampleMultipart())
        XCTAssertTrue(s.contains("new FormData()"))
        XCTAssertTrue(s.contains("form.append(\"name\", \"alice\")"))
    }

    func testJSStringEscapesQuoteAndBackslash() {
        let s = JSFetchExporter.jsString(#"a"b\c"#)
        XCTAssertEqual(s, #""a\"b\\c""#)
    }

    func testJSStringEscapesScriptCloseTag() {
        // Defends against breaking out of inline `<script>...</script>`.
        let s = JSFetchExporter.jsString("</script>")
        XCTAssertFalse(s.contains("</"))
        XCTAssertTrue(s.contains(#"<\/"#))
    }

    // MARK: - JS axios

    func testJSAxiosImportsAxios() {
        let s = JSAxiosExporter.export(sampleJSON())
        XCTAssertTrue(s.contains("import axios from \"axios\""))
        XCTAssertTrue(s.contains("axios.request("))
        XCTAssertTrue(s.contains("data: {\"k\":\"v\"}"))
    }

    // MARK: - Node http

    func testNodeHTTPPicksHTTPSForTLSHost() {
        let s = NodeHTTPExporter.export(sampleJSON())
        XCTAssertTrue(s.contains("require(\"https\")"))
        XCTAssertTrue(s.contains("port: 443"))
        XCTAssertTrue(s.contains("path: \"/items\""))
    }

    func testNodeHTTPHTTPHostUsesPort80() {
        var d = sampleGet()
        d.url = "http://x.test/items?q=1"
        d.url = d.rebuildURL()
        let s = NodeHTTPExporter.export(d)
        XCTAssertTrue(s.contains("require(\"http\")"))
        XCTAssertTrue(s.contains("port: 80"))
    }

    // MARK: - PowerShell

    func testPowerShellInvokeWebRequest() {
        let s = PowerShellExporter.export(sampleJSON())
        XCTAssertTrue(s.contains("Invoke-WebRequest"))
        XCTAssertTrue(s.contains("-Uri 'https://x.test/items'"))
        XCTAssertTrue(s.contains("-Method POST"))
        XCTAssertTrue(s.contains("$headers = @{"))
    }

    func testPowerShellEscapesSingleQuoteByDoubling() {
        var d = sampleGet()
        d.headers = [DraftKeyValue(key: "X-Note", value: "it's fine")]
        let s = PowerShellExporter.export(d)
        XCTAssertTrue(s.contains("'it''s fine'"))
    }

    // MARK: - ExportFormat surface

    func testAllSnippetFormatsAdvertiseExtensions() {
        for f in ExportFormat.allCases {
            XCTAssertFalse(f.fileExtension.isEmpty, "format \(f) missing extension")
            XCTAssertFalse(f.displayName.isEmpty, "format \(f) missing displayName")
        }
    }
}

import XCTest
@testable import Snag

@MainActor
final class RequestDraftTests: XCTestCase {

    func testRequestDraftDataCodableRoundTrip() throws {
        let original = RequestDraftData(
            id: "abc-123",
            name: "Login",
            url: "https://api.example.com/login?x=1",
            method: "POST",
            headers: [
                DraftKeyValue(key: "Content-Type", value: "application/json"),
                DraftKeyValue(key: "X-Auth", value: "secret", enabled: false),
            ],
            queryParams: [DraftKeyValue(key: "x", value: "1")],
            bodyBase64: Data("{\"a\":1}".utf8).base64EncodedString(),
            bodyEncoding: .json,
            bodyContentType: "application/json",
            followRedirects: false,
            timeoutSeconds: 12,
            allowInvalidCertificates: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(RequestDraftData.self, from: data)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.url, original.url)
        XCTAssertEqual(restored.method, original.method)
        XCTAssertEqual(restored.headers, original.headers)
        XCTAssertEqual(restored.queryParams, original.queryParams)
        XCTAssertEqual(restored.bodyBase64, original.bodyBase64)
        XCTAssertEqual(restored.bodyEncoding, original.bodyEncoding)
        XCTAssertEqual(restored.bodyContentType, original.bodyContentType)
        XCTAssertEqual(restored.followRedirects, original.followRedirects)
        XCTAssertEqual(restored.timeoutSeconds, original.timeoutSeconds)
        XCTAssertEqual(restored.allowInvalidCertificates, original.allowInvalidCertificates)
    }

    func testParseQueryItems() {
        let rows = RequestDraftData.parseQueryItems(from: "https://x.test/path?a=1&b=&c=hello%20world")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].key, "a")
        XCTAssertEqual(rows[0].value, "1")
        XCTAssertEqual(rows[1].key, "b")
        XCTAssertEqual(rows[1].value, "")
        XCTAssertEqual(rows[2].key, "c")
        XCTAssertEqual(rows[2].value, "hello world")
    }

    func testRebuildURLPreservesOrderAndDropsDisabled() {
        var data = RequestDraftData(url: "https://x.test/path")
        data.queryParams = [
            DraftKeyValue(key: "a", value: "1"),
            DraftKeyValue(key: "b", value: "2", enabled: false),
            DraftKeyValue(key: "c", value: "3"),
        ]
        let rebuilt = data.rebuildURL()
        XCTAssertEqual(rebuilt, "https://x.test/path?a=1&c=3")
    }

    func testToURLRequestRejectsNonHTTPScheme() {
        var data = RequestDraftData(url: "ftp://example.com")
        data.method = "GET"
        XCTAssertThrowsError(try data.toURLRequest()) { error in
            guard case DraftValidationError.invalidScheme = error else {
                XCTFail("Expected invalidScheme, got \(error)")
                return
            }
        }
    }

    func testToURLRequestRejectsURLWithoutScheme() {
        // URL("not a url at all") parses, but has no scheme — must be rejected.
        let data = RequestDraftData(url: "not a url at all")
        XCTAssertThrowsError(try data.toURLRequest()) { error in
            guard case DraftValidationError.invalidScheme = error else {
                XCTFail("Expected invalidScheme, got \(error)")
                return
            }
        }
    }

    func testToURLRequestRejectsHeaderWithCRLF() {
        var data = RequestDraftData(url: "https://x.test/")
        data.headers = [DraftKeyValue(key: "X-Bad", value: "evil\r\nInjected: yes")]
        XCTAssertThrowsError(try data.toURLRequest()) { error in
            guard case DraftValidationError.invalidHeader = error else {
                XCTFail("Expected invalidHeader, got \(error)")
                return
            }
        }
    }

    func testToURLRequestSetsMethodHeadersAndBody() throws {
        var data = RequestDraftData(url: "https://x.test/path?a=1", method: "post")
        data.headers = [
            DraftKeyValue(key: "Content-Type", value: "application/json"),
            DraftKeyValue(key: "X-Off", value: "no", enabled: false),
        ]
        data.queryParams = [DraftKeyValue(key: "a", value: "1")]
        data.bodyBase64 = Data("{\"x\":1}".utf8).base64EncodedString()

        let req = try data.toURLRequest()
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(req.value(forHTTPHeaderField: "X-Off"))
        XCTAssertEqual(req.httpBody, Data("{\"x\":1}".utf8))
        XCTAssertEqual(req.url?.absoluteString, "https://x.test/path?a=1")
    }

    func testFromPacketCopiesURLMethodAndHeaders() {
        let info = SnagRequestInfo()
        info.url = "https://x.test/login?u=alice"
        info.requestMethod = .post
        info.requestHeaders = ["Content-Type": "application/json", "Authorization": "Bearer t"]
        info.requestBody = Data("{\"u\":\"alice\"}".utf8).base64EncodedString()

        let packet = SnagPacket()
        packet.requestInfo = info

        let draft = RequestDraftData.from(packet)
        XCTAssertEqual(draft.url, "https://x.test/login?u=alice")
        XCTAssertEqual(draft.method, "POST")
        XCTAssertEqual(draft.headers.count, 2)
        XCTAssertTrue(draft.headers.contains(where: { $0.key == "Authorization" && $0.value == "Bearer t" }))
        XCTAssertEqual(draft.queryParams.count, 1)
        XCTAssertEqual(draft.queryParams.first?.key, "u")
        XCTAssertEqual(draft.bodyEncoding, .json)
        XCTAssertEqual(draft.bodyContentType, "application/json")
    }

    func testRequestDraftDataDecodesWithoutMultipartParts() throws {
        // Older persisted JSON (pre-multipart) must still decode — multipartParts is new.
        let legacy = """
        {
          "id":"x",
          "name":"",
          "url":"https://x.test/",
          "method":"GET",
          "headers":[],
          "queryParams":[],
          "bodyEncoding":"text",
          "followRedirects":true,
          "timeoutSeconds":30,
          "allowInvalidCertificates":false,
          "createdAt":"2026-01-01T00:00:00Z",
          "updatedAt":"2026-01-01T00:00:00Z"
        }
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let data = try dec.decode(RequestDraftData.self, from: Data(legacy.utf8))
        XCTAssertEqual(data.multipartParts, [])
    }

    func testMultipartBodyEncodesTextAndFileParts() throws {
        // Write a tiny file to disk to use as a file part.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("snag-multipart-\(UUID().uuidString).txt")
        let payload = Data("hello-file".utf8)
        try payload.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let parts = [
            DraftMultipartPart(name: "title", kind: .text, textValue: "hi"),
            DraftMultipartPart(name: "skipped", kind: .text, textValue: "no", enabled: false),
            DraftMultipartPart(name: "upload", kind: .file,
                               fileURL: tmp.absoluteString,
                               fileName: "renamed.txt",
                               contentType: "text/plain"),
        ]
        let (body, ct) = try RequestDraftData.buildMultipartBody(parts: parts, boundary: "B")

        XCTAssertEqual(ct, "multipart/form-data; boundary=B")
        let s = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhi\r\n"))
        XCTAssertTrue(s.contains("Content-Disposition: form-data; name=\"upload\"; filename=\"renamed.txt\""))
        XCTAssertTrue(s.contains("Content-Type: text/plain"))
        XCTAssertTrue(s.contains("hello-file"))
        XCTAssertFalse(s.contains("name=\"skipped\""), "Disabled part must not be encoded")
        XCTAssertTrue(s.hasSuffix("--B--\r\n"))
    }

    func testToURLRequestSetsMultipartContentTypeAndDropsUserContentType() throws {
        var data = RequestDraftData(url: "https://x.test/upload", method: "POST")
        data.bodyEncoding = .multipart
        data.headers = [
            DraftKeyValue(key: "Content-Type", value: "application/json"),
            DraftKeyValue(key: "Authorization", value: "Bearer t"),
        ]
        data.multipartParts = [DraftMultipartPart(name: "k", kind: .text, textValue: "v")]

        let req = try data.toURLRequest()
        let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(ct.hasPrefix("multipart/form-data; boundary="),
                      "User-set Content-Type must be replaced with multipart's, got \(ct)")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertNotNil(req.httpBody)
    }

    func testDisplayNameFallsBackToMethodAndPath() {
        var data = RequestDraftData()
        data.url = "https://x.test/users/42"
        data.method = "GET"
        XCTAssertEqual(data.displayName, "GET /users/42")

        data.name = "Get User"
        XCTAssertEqual(data.displayName, "Get User")
    }
}

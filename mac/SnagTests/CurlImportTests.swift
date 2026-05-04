import XCTest
@testable import Snag

@MainActor
final class CurlImportTests: XCTestCase {

    // MARK: - Tokenizer

    func testTokenizerSplitsOnUnquotedWhitespace() throws {
        let toks = try CurlTokenizer.tokenize(#"curl -H "X-A: 1" 'https://x.test/'"#)
        XCTAssertEqual(toks, ["curl", "-H", "X-A: 1", "https://x.test/"])
    }

    func testTokenizerHandlesLineContinuation() throws {
        let input = "curl \\\n  -X POST \\\n  https://x.test/"
        let toks = try CurlTokenizer.tokenize(input)
        XCTAssertEqual(toks, ["curl", "-X", "POST", "https://x.test/"])
    }

    func testTokenizerANSICQuoting() throws {
        let toks = try CurlTokenizer.tokenize(#"curl $'https://x.test/é'"#)
        // \u escapes are not in our minimal set; \e/é must come from \xHH or literal.
        // Use \x escape:
        let toks2 = try CurlTokenizer.tokenize(#"curl $'a\tb'"#)
        XCTAssertEqual(toks2, ["curl", "a\tb"])
        XCTAssertEqual(toks.count, 2) // tokenized — we don't decode \u
    }

    func testTokenizerThrowsOnUnterminatedQuote() {
        XCTAssertThrowsError(try CurlTokenizer.tokenize(#"curl 'unterminated"#)) { e in
            XCTAssertEqual(e as? CurlParseError, .unterminatedQuote)
        }
    }

    // MARK: - Plan §7.1: plain GET

    func testPlainGet() throws {
        let r = try CurlImporter.parse("curl https://x.test/path?a=1")
        XCTAssertEqual(r.draft.method, "GET")
        XCTAssertEqual(r.draft.queryParams.count, 1)
        XCTAssertEqual(r.draft.queryParams.first?.key, "a")
        XCTAssertEqual(r.draft.queryParams.first?.value, "1")
    }

    // MARK: - Plan §7.2: quoted URL with spaces

    func testQuotedURLWithSpaces() throws {
        let r = try CurlImporter.parse(#"curl 'https://x.test/a%20b'"#)
        XCTAssertEqual(r.draft.method, "GET")
        XCTAssertTrue(r.draft.url.contains("a%20b"))
    }

    // MARK: - Plan §7.3: multiple -H lines

    func testMultipleHeaders() throws {
        let r = try CurlImporter.parse(
            "curl -H 'X-A: 1' -H 'X-B: 2' -H 'x-a: dup' https://x.test/"
        )
        XCTAssertEqual(r.draft.headers.count, 3)
        XCTAssertEqual(r.draft.headers[0].key, "X-A")
        XCTAssertEqual(r.draft.headers[2].key, "x-a")
    }

    // MARK: - Plan §7.4: POST JSON

    func testPostJsonBody() throws {
        let cmd = #"curl -X POST -d '{"a":1}' -H 'Content-Type: application/json' https://x.test/"#
        let r = try CurlImporter.parse(cmd)
        XCTAssertEqual(r.draft.method, "POST")
        XCTAssertEqual(r.draft.bodyEncoding, .json)
        let body = Data(base64Encoded: r.draft.bodyBase64 ?? "") ?? Data()
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"a":1}"#)
    }

    // MARK: - Plan §7.5: -d a=1 -d b=2

    func testRepeatedDataChunksJoinWithAmpersand() throws {
        let r = try CurlImporter.parse("curl -d a=1 -d b=2 https://x.test/")
        XCTAssertEqual(r.draft.method, "POST")
        let body = Data(base64Encoded: r.draft.bodyBase64 ?? "") ?? Data()
        XCTAssertEqual(String(data: body, encoding: .utf8), "a=1&b=2")
        let ct = r.draft.headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }
        XCTAssertEqual(ct?.value, "application/x-www-form-urlencoded")
    }

    // MARK: - Plan §7.6: multipart with file + text

    func testMultipartFileAndTextWithoutConsent() throws {
        let r = try CurlImporter.parse(
            "curl -F file=@/tmp/x.png -F name=alice https://x.test/"
        )
        XCTAssertEqual(r.draft.method, "POST")
        XCTAssertEqual(r.draft.bodyEncoding, .multipart)
        XCTAssertEqual(r.draft.multipartParts.count, 2)

        let fileP = r.draft.multipartParts.first { $0.name == "file" }!
        XCTAssertEqual(fileP.kind, .file)
        XCTAssertNil(fileP.fileURL, "Without consent, file part is left empty")

        let nameP = r.draft.multipartParts.first { $0.name == "name" }!
        XCTAssertEqual(nameP.kind, .text)
        XCTAssertEqual(nameP.textValue, "alice")

        XCTAssertTrue(r.warnings.contains { $0.contains("/tmp/x.png") })
    }

    // MARK: - Plan §7.7: multipart with type+filename modifiers

    func testMultipartTypeAndFilenameModifiers() throws {
        let r = try CurlImporter.parse(
            #"curl -F 'file=@/tmp/x.png;type=image/png;filename=foo.png' https://x.test/"#,
            options: CurlImportOptions(loadLocalFiles: true)
        )
        let fileP = r.draft.multipartParts.first!
        XCTAssertEqual(fileP.contentType, "image/png")
        XCTAssertEqual(fileP.fileName, "foo.png")
        XCTAssertEqual(fileP.kind, .file)
        XCTAssertTrue(fileP.fileURL?.contains("/tmp/x.png") ?? false)
    }

    // MARK: - Plan §7.8: -u user:pass

    func testBasicAuthSynthesizesAuthorizationHeader() throws {
        let r = try CurlImporter.parse("curl -u user:pass https://x.test/")
        let auth = r.draft.headers.first { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame }
        XCTAssertEqual(auth?.value, "Basic dXNlcjpwYXNz")
    }

    func testBasicAuthDoesNotOverrideUserHeader() throws {
        let r = try CurlImporter.parse(
            "curl -u user:pass -H 'Authorization: Bearer t' https://x.test/"
        )
        let auth = r.draft.headers.filter { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame }
        XCTAssertEqual(auth.count, 1)
        XCTAssertEqual(auth.first?.value, "Bearer t")
    }

    // MARK: - Plan §7.9: cookie

    func testCookieHeaderFromDashB() throws {
        let r = try CurlImporter.parse(
            #"curl -b 'session=abc; theme=dark' https://x.test/"#
        )
        let cookie = r.draft.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }
        XCTAssertEqual(cookie?.value, "session=abc; theme=dark")
    }

    // MARK: - Plan §7.10: --compressed

    func testCompressedSynthesizesAcceptEncoding() throws {
        let r = try CurlImporter.parse("curl --compressed https://x.test/")
        let ae = r.draft.headers.first { $0.key.caseInsensitiveCompare("Accept-Encoding") == .orderedSame }
        XCTAssertEqual(ae?.value, "gzip, deflate, br")
    }

    func testCompressedDoesNotOverrideUserAcceptEncoding() throws {
        let r = try CurlImporter.parse(
            "curl --compressed -H 'Accept-Encoding: br' https://x.test/"
        )
        let aes = r.draft.headers.filter { $0.key.caseInsensitiveCompare("Accept-Encoding") == .orderedSame }
        XCTAssertEqual(aes.count, 1)
        XCTAssertEqual(aes.first?.value, "br")
    }

    // MARK: - Plan §7.11: -G --data-urlencode

    func testGetWithDataUrlencodeBuildsQuery() throws {
        let r = try CurlImporter.parse(
            #"curl -G --data-urlencode 'q=hello world' https://x.test/"#
        )
        XCTAssertEqual(r.draft.method, "GET")
        XCTAssertNil(r.draft.bodyBase64)
        XCTAssertEqual(r.draft.queryParams.count, 1)
        XCTAssertEqual(r.draft.queryParams.first?.key, "q")
        XCTAssertEqual(r.draft.queryParams.first?.value, "hello world")
        XCTAssertTrue(r.draft.url.contains("q=hello%20world"))
    }

    // MARK: - Plan §7.12: line continuations

    func testFourLineContinuation() throws {
        let cmd = """
        curl -X POST \\
          -H 'Content-Type: application/json' \\
          -d '{"a":1}' \\
          https://x.test/
        """
        let r = try CurlImporter.parse(cmd)
        XCTAssertEqual(r.draft.method, "POST")
        XCTAssertEqual(r.draft.url, "https://x.test/")
        XCTAssertEqual(r.draft.bodyEncoding, .json)
    }

    // MARK: - Plan §7.13: ANSI-C quoting

    func testAnsiCQuoting() throws {
        let r = try CurlImporter.parse(#"curl $'https://x.test/path?a=1'"#)
        XCTAssertTrue(r.draft.url.hasPrefix("https://x.test/path"))
    }

    // MARK: - Plan §7.14: --url and -I (HEAD)

    func testUrlFlagAndHeadFlag() throws {
        let r = try CurlImporter.parse("curl --url https://x.test -I")
        XCTAssertEqual(r.draft.method, "HEAD")
        XCTAssertEqual(r.draft.url, "https://x.test")
    }

    // MARK: - Plan §7.15: warnings for unsupported network flags

    func testUnsupportedNetworkFlagsWarn() throws {
        let r = try CurlImporter.parse(
            "curl --location-trusted --resolve x:443:1.2.3.4 --http2 --cookie-jar /tmp/c https://x.test/"
        )
        let joined = r.warnings.joined(separator: "\n")
        XCTAssertTrue(joined.contains("location-trusted"))
        XCTAssertTrue(joined.contains("resolve"))
        XCTAssertTrue(joined.contains("http2"))
        XCTAssertTrue(joined.contains("cookie-jar"))
    }

    // MARK: - Plan §7.16: --data-binary @file without consent

    func testDataBinaryFileRefRequiresConsent() throws {
        let r = try CurlImporter.parse(
            "curl --data-binary @/tmp/body.bin https://x.test/"
        )
        XCTAssertTrue(r.warnings.contains { $0.contains("/tmp/body.bin") })
        // Body is empty — file not read.
        let body = Data(base64Encoded: r.draft.bodyBase64 ?? "") ?? Data()
        XCTAssertTrue(body.isEmpty)
    }

    // MARK: - Plan §7.17: error cases

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try CurlImporter.parse("")) { e in
            XCTAssertEqual(e as? CurlParseError, .notACurlCommand)
        }
    }

    func testMissingURLThrows() {
        XCTAssertThrowsError(try CurlImporter.parse("curl -X POST")) { e in
            XCTAssertEqual(e as? CurlParseError, .noURL)
        }
    }

    func testUnterminatedQuoteThrows() {
        XCTAssertThrowsError(try CurlImporter.parse(#"curl 'oops"#)) { e in
            XCTAssertEqual(e as? CurlParseError, .unterminatedQuote)
        }
    }

    func testNotCurlThrows() {
        XCTAssertThrowsError(try CurlImporter.parse("wget https://x.test/")) { e in
            XCTAssertEqual(e as? CurlParseError, .notACurlCommand)
        }
    }

    // MARK: - Short flag stacking

    func testStackedShortFlags() throws {
        let r = try CurlImporter.parse("curl -kL https://x.test/")
        XCTAssertTrue(r.draft.allowInvalidCertificates)
        // followRedirects is forced true regardless; this just shouldn't throw.
        XCTAssertEqual(r.draft.method, "GET")
    }

    func testShortFlagWithGluedValue() throws {
        let r = try CurlImporter.parse("curl -Hfoo:bar https://x.test/")
        XCTAssertEqual(r.draft.headers.count, 1)
        XCTAssertEqual(r.draft.headers.first?.key, "foo")
        XCTAssertEqual(r.draft.headers.first?.value, "bar")
    }

    // MARK: - URL that already has query params + -G

    func testUrlExistingQueryPreservedWhenNoG() throws {
        let r = try CurlImporter.parse(
            #"curl 'https://x.test/path?existing=1'"#
        )
        XCTAssertEqual(r.draft.queryParams.count, 1)
        XCTAssertEqual(r.draft.queryParams.first?.key, "existing")
    }

    // MARK: - Method casing preserved

    func testMethodCasingPreserved() throws {
        let r = try CurlImporter.parse("curl -X propfind https://x.test/")
        XCTAssertEqual(r.draft.method, "propfind")
    }
}

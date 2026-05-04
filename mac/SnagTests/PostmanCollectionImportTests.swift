import XCTest
@testable import Snag

@MainActor
final class PostmanCollectionImportTests: XCTestCase {

    private func parse(_ json: String) throws -> ImportableBatch {
        try PostmanCollectionImporter.parse(.text(json), options: CurlImportOptions())
    }

    // MARK: - canHandle

    func testCanHandleRecognizesCollectionShape() {
        let pm = #"{"info":{"name":"x","schema":"v2.1.0"},"item":[]}"#
        XCTAssertTrue(PostmanCollectionImporter.canHandle(.text(pm)))
    }

    func testCanHandleRejectsHAR() {
        let har = #"{"log":{"version":"1.2","entries":[]}}"#
        XCTAssertFalse(PostmanCollectionImporter.canHandle(.text(har)))
    }

    // MARK: - Plan §7: Postman v2.1 with 1 folder, 2 requests, raw JSON body

    func testFolderWithTwoRequestsRawJSONBody() throws {
        let pm = """
        {
          "info": {
            "name": "Test",
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
          },
          "item": [
            {
              "name": "Auth",
              "item": [
                {
                  "name": "Login",
                  "request": {
                    "method": "POST",
                    "header": [{ "key": "Content-Type", "value": "application/json" }],
                    "body": {
                      "mode": "raw",
                      "raw": "{\\"u\\":\\"a\\"}",
                      "options": { "raw": { "language": "json" } }
                    },
                    "url": { "raw": "https://x.test/login", "host": ["x", "test"], "path": ["login"] }
                  }
                },
                {
                  "name": "Logout",
                  "request": {
                    "method": "POST",
                    "header": [],
                    "url": "https://x.test/logout"
                  }
                }
              ]
            }
          ]
        }
        """
        let batch = try parse(pm)
        XCTAssertEqual(batch.requests.count, 2)
        XCTAssertNotNil(batch.folders, "Postman batches carry a folder tree")

        let login = batch.requests[0]
        XCTAssertEqual(login.folderPath, ["Auth"])
        XCTAssertEqual(login.draftData.method, "POST")
        XCTAssertEqual(login.draftData.bodyEncoding, .json)

        let logout = batch.requests[1]
        XCTAssertEqual(logout.folderPath, ["Auth"])
        XCTAssertEqual(logout.draftData.url, "https://x.test/logout")
    }

    // MARK: - Auth basic / bearer → Authorization header

    func testBasicAuthMapsToBase64AuthorizationHeader() throws {
        let pm = """
        {
          "info": { "name": "x", "schema": "v2.1.0" },
          "item": [{
            "name": "R",
            "request": {
              "method": "GET",
              "url": "https://x.test/",
              "auth": {
                "type": "basic",
                "basic": [
                  { "key": "username", "value": "u" },
                  { "key": "password", "value": "p" }
                ]
              }
            }
          }]
        }
        """
        let batch = try parse(pm)
        let auth = batch.requests[0].draftData.headers.first {
            $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
        }
        XCTAssertNotNil(auth)
        // base64("u:p") == "dTpw"
        XCTAssertEqual(auth?.value, "Basic dTpw")
    }

    func testBearerAuthMapsToAuthorizationHeader() throws {
        let pm = """
        {
          "info": { "name": "x", "schema": "v2.1.0" },
          "item": [{
            "name": "R",
            "request": {
              "method": "GET",
              "url": "https://x.test/",
              "auth": {
                "type": "bearer",
                "bearer": [{ "key": "token", "value": "abc.def" }]
              }
            }
          }]
        }
        """
        let batch = try parse(pm)
        let auth = batch.requests[0].draftData.headers.first {
            $0.key.caseInsensitiveCompare("Authorization") == .orderedSame
        }
        XCTAssertEqual(auth?.value, "Bearer abc.def")
    }

    // MARK: - Variables surface a warning, pass through literally

    func testUnresolvedPostmanVariableYieldsWarning() throws {
        let pm = """
        {
          "info": { "name": "x", "schema": "v2.1.0" },
          "item": [{
            "name": "R",
            "request": {
              "method": "GET",
              "url": "{{baseUrl}}/items"
            }
          }]
        }
        """
        let batch = try parse(pm)
        XCTAssertEqual(batch.requests.count, 1)
        // The URL gets percent-encoded by rebuildURL, but the placeholder still
        // round-trips (decoded `%7B%7BbaseUrl%7D%7D` == `{{baseUrl}}`).
        let url = batch.requests[0].draftData.url
        XCTAssertTrue(url.contains("{{baseUrl}}") || url.contains("%7B%7BbaseUrl%7D%7D"))
        XCTAssertTrue(
            batch.requests[0].warnings.contains { $0.contains("{{baseUrl}}") || $0.contains("variable") },
            "Expected a warning about the unresolved variable, got: \(batch.requests[0].warnings)"
        )
    }

    // MARK: - formdata body → multipart parts

    func testFormDataBodyMapsToMultipart() throws {
        let pm = """
        {
          "info": { "name": "x", "schema": "v2.1.0" },
          "item": [{
            "name": "Upload",
            "request": {
              "method": "POST",
              "url": "https://x.test/up",
              "body": {
                "mode": "formdata",
                "formdata": [
                  { "key": "name", "type": "text", "value": "alice" },
                  { "key": "avatar", "type": "file", "src": "/tmp/a.png", "contentType": "image/png" }
                ]
              }
            }
          }]
        }
        """
        let batch = try parse(pm)
        let req = batch.requests[0]
        XCTAssertEqual(req.draftData.bodyEncoding, .multipart)
        XCTAssertEqual(req.draftData.multipartParts.count, 2)
        XCTAssertEqual(req.draftData.multipartParts[0].kind, .text)
        XCTAssertEqual(req.draftData.multipartParts[0].textValue, "alice")
        XCTAssertEqual(req.draftData.multipartParts[1].kind, .file)
        XCTAssertEqual(req.draftData.multipartParts[1].fileURL, "/tmp/a.png")
    }
}

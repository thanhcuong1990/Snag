import XCTest
@testable import Snag

class CURLRepresentationTests: XCTestCase {
    
    // MARK: - Helper
    
    private func createRequestInfo(
        url: String? = nil,
        method: RequestMethod? = .get,
        headers: [String: String]? = nil,
        body: String? = nil
    ) -> SnagRequestInfo {
        let info = SnagRequestInfo()
        info.url = url
        info.requestMethod = method
        info.requestHeaders = headers
        info.requestBody = body
        return info
    }
    
    private func curlString(for info: SnagRequestInfo) -> String {
        let representation = CURLRepresentation(requestInfo: info)
        return representation.rawString ?? ""
    }
    
    // MARK: - Basic Tests
    
    func testBasicGetRequest() {
        let info = createRequestInfo(url: "https://api.example.com/users")
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.hasPrefix("curl 'https://api.example.com/users'"))
    }
    
    func testURLWithQueryParameters() {
        // This was the original bug - & characters need quoting
        let info = createRequestInfo(url: "https://api.example.com?foo=1&bar=2&baz=3")
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("'https://api.example.com?foo=1&bar=2&baz=3'"),
                      "URL with & should be wrapped in single quotes")
    }
    
    // MARK: - HTTP Methods
    
    func testPostRequest() {
        let info = createRequestInfo(
            url: "https://api.example.com/users",
            method: .post,
            body: "{\"name\": \"John\"}"
        )
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("-d '{\"name\": \"John\"}'"))
    }
    
    func testPutRequest() {
        let info = createRequestInfo(url: "https://api.example.com/users/1", method: .put)
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("-X PUT"))
    }
    
    func testDeleteRequest() {
        let info = createRequestInfo(url: "https://api.example.com/users/1", method: .delete)
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("-X DELETE"))
    }
    
    func testPatchRequest() {
        let info = createRequestInfo(url: "https://api.example.com/users/1", method: .patch)
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("-X PATCH"))
    }
    
    func testHeadRequest() {
        let info = createRequestInfo(url: "https://api.example.com/users", method: .head)
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("--head"))
        XCTAssertFalse(curl.contains("-X HEAD"), "HEAD should use --head flag, not -X")
    }
    
    // MARK: - Headers
    
    func testBasicHeaders() {
        let info = createRequestInfo(
            url: "https://api.example.com",
            headers: ["Content-Type": "application/json"]
        )
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("-H 'Content-Type: application/json'"))
    }
    
    func testHeadersWithSingleQuotes() {
        // Critical: Single quotes in header values must be escaped
        let info = createRequestInfo(
            url: "https://api.example.com",
            headers: ["Authorization": "Bearer it's_a_token"]
        )
        let curl = curlString(for: info)
        
        // ' should become '\'' in shell escaping
        XCTAssertTrue(curl.contains("it'\\''s_a_token"),
                      "Single quotes in headers should be escaped as '\\''")
    }
    
    func testCookieHeaderExcluded() {
        let info = createRequestInfo(
            url: "https://api.example.com",
            headers: [
                "Content-Type": "application/json",
                "Cookie": "session=abc123"
            ]
        )
        let curl = curlString(for: info)
        
        XCTAssertFalse(curl.contains("Cookie"), "Cookie header should be excluded")
        XCTAssertTrue(curl.contains("Content-Type"))
    }
    
    // MARK: - Body
    
    func testBodyWithSingleQuotes() {
        // Critical: Single quotes in body must be escaped (e.g., O'Brien)
        let info = createRequestInfo(
            url: "https://api.example.com/users",
            method: .post,
            body: "{\"name\": \"O'Brien\"}"
        )
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("O'\\''Brien"),
                      "Single quotes in body should be escaped as '\\''")
    }
    
    func testJsonBody() {
        let jsonBody = """
        {"user": {"name": "John", "age": 30}}
        """
        let info = createRequestInfo(
            url: "https://api.example.com/users",
            method: .post,
            body: jsonBody
        )
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("-d"))
    }
    
    // MARK: - Edge Cases
    
    func testNilURL() {
        let info = createRequestInfo(url: nil)
        let curl = curlString(for: info)
        
        XCTAssertEqual(curl, "", "Nil URL should return empty string")
    }
    
    func testURLWithSingleQuote() {
        // Edge case: URL containing single quote
        let info = createRequestInfo(url: "https://api.example.com/search?q=it's")
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.contains("it'\\''s"),
                      "Single quotes in URL should be escaped")
    }
    
    func testCompleteRequest() {
        // Full integration test with all components
        let info = createRequestInfo(
            url: "https://api.example.com/users?page=1&limit=10",
            method: .post,
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer abc123"
            ],
            body: "{\"name\": \"John Doe\"}"
        )
        let curl = curlString(for: info)
        
        XCTAssertTrue(curl.hasPrefix("curl"))
        XCTAssertTrue(curl.contains("page=1&limit=10"))
        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("-H 'Content-Type: application/json'"))
        XCTAssertTrue(curl.contains("-H 'Authorization: Bearer abc123'"))
        XCTAssertTrue(curl.contains("-d '{\"name\": \"John Doe\"}'"))
    }
}

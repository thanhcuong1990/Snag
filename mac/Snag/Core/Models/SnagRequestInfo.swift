import Cocoa

enum RequestMethod: String, Codable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case delete = "DELETE"
  case patch = "PATCH"
  case head = "HEAD"
}

class SnagRequestInfo: Codable {

    var url: String?
    var requestHeaders: [String: String]? { didSet { _lowercasedRequestHeaders = nil } }
    var requestBody: String? { didSet { _cachedRequestBodyByteCount = nil } }
    var requestMethod: RequestMethod?

    var responseHeaders: [String: String]? { didSet { _lowercasedResponseHeaders = nil } }
    var responseData: String? { didSet { _cachedResponseDataByteCount = nil } }

    var statusCode: String?

    var startDate: Date?
    var endDate: Date?

    private var _cachedRequestBodyByteCount: Int?
    private var _cachedResponseDataByteCount: Int?

    // HTTP header names are case-insensitive (RFC 7230). We keep the original-cased
    // dict for display, and build a lazy lowercased lookup table for O(1) access by
    // canonical key.
    private var _lowercasedRequestHeaders: [String: String]?
    private var _lowercasedResponseHeaders: [String: String]?

    private static func lowercasedHeaders(_ headers: [String: String]?) -> [String: String]? {
        guard let headers = headers else { return nil }
        var result: [String: String] = [:]
        result.reserveCapacity(headers.count)
        for (k, v) in headers { result[k.lowercased()] = v }
        return result
    }

    var requestBodyByteCount: Int {
        if let cached = _cachedRequestBodyByteCount { return cached }
        let count = requestBody.flatMap { Data(base64Encoded: $0)?.count } ?? 0
        _cachedRequestBodyByteCount = count
        return count
    }

    var responseDataByteCount: Int {
        if let cached = _cachedResponseDataByteCount { return cached }
        let count = responseData.flatMap { Data(base64Encoded: $0)?.count } ?? 0
        _cachedResponseDataByteCount = count
        return count
    }

    func responseHeader(_ name: String) -> String? {
        if let cached = _lowercasedResponseHeaders {
            return cached[name.lowercased()]
        }
        let built = Self.lowercasedHeaders(responseHeaders)
        _lowercasedResponseHeaders = built
        return built?[name.lowercased()]
    }

    func requestHeader(_ name: String) -> String? {
        if let cached = _lowercasedRequestHeaders {
            return cached[name.lowercased()]
        }
        let built = Self.lowercasedHeaders(requestHeaders)
        _lowercasedRequestHeaders = built
        return built?[name.lowercased()]
    }

    var responseContentType: String? {
        return responseHeader("content-type")
    }

    var requestContentType: String? {
        return requestHeader("content-type")
    }

    enum CodingKeys: String, CodingKey {
        case url
        case requestHeaders
        case requestBody
        case requestMethod
        case responseHeaders
        case responseData
        case statusCode
        case startDate
        case endDate
    }
    
    init() {}
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.requestHeaders = try container.decodeIfPresent([String: String].self, forKey: .requestHeaders)
        self.requestBody = try container.decodeIfPresent(String.self, forKey: .requestBody)
        self.requestMethod = try container.decodeIfPresent(RequestMethod.self, forKey: .requestMethod)
        self.responseHeaders = try container.decodeIfPresent([String: String].self, forKey: .responseHeaders)
        self.responseData = try container.decodeIfPresent(String.self, forKey: .responseData)
        
        if let statusCodeInt = try? container.decodeIfPresent(Int.self, forKey: .statusCode) {
            self.statusCode = String(statusCodeInt)
        } else {
            self.statusCode = try container.decodeIfPresent(String.self, forKey: .statusCode)
        }
        
        self.startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        self.endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
    }
}

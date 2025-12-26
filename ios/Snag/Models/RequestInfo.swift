import Foundation

public struct SnagRequestInfo: Sendable {
    public var url: URL?
    public var requestHeaders: [String: String]?
    public var requestBody: Data?
    public var requestMethod: String?
    
    public var responseHeaders: [String: String]?
    public var responseData: Data?
    public var statusCode: String?
    
    public var startDate: Date?
    public var endDate: Date?
    
    public init() {}
    
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
}

extension SnagRequestInfo: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        self.requestHeaders = try container.decodeIfPresent([String: String].self, forKey: .requestHeaders)
        self.requestBody = try container.decodeIfPresent(Data.self, forKey: .requestBody)
        self.requestMethod = try container.decodeIfPresent(String.self, forKey: .requestMethod)
        self.responseHeaders = try container.decodeIfPresent([String: String].self, forKey: .responseHeaders)
        self.responseData = try container.decodeIfPresent(Data.self, forKey: .responseData)
        
        if let statusCodeInt = try? container.decodeIfPresent(Int.self, forKey: .statusCode) {
            self.statusCode = String(statusCodeInt)
        } else {
            self.statusCode = try container.decodeIfPresent(String.self, forKey: .statusCode)
        }
        
        self.startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        self.endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(requestHeaders, forKey: .requestHeaders)
        try container.encodeIfPresent(requestBody, forKey: .requestBody)
        try container.encodeIfPresent(requestMethod, forKey: .requestMethod)
        try container.encodeIfPresent(responseHeaders, forKey: .responseHeaders)
        try container.encodeIfPresent(responseData, forKey: .responseData)
        try container.encodeIfPresent(statusCode, forKey: .statusCode)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
    }
}


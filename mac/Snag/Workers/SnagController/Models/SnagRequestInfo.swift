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
    var requestHeaders: [String: String]?
    var requestBody: String?
    var requestMethod: RequestMethod?
    
    var responseHeaders: [String: String]?
    var responseData: String?
    
    var statusCode: String?
    
    var startDate: Date?
    var endDate: Date?
    
    var responseContentType: String? {
        return responseHeaders?["Content-Type"] ?? responseHeaders?["content-type"]
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
        
        if let statusCodeInt = try? container.decodeIfPresent(Int.self, forKey: .statusCode), let unwrappedInt = statusCodeInt {
            self.statusCode = String(unwrappedInt)
        } else {
            self.statusCode = try container.decodeIfPresent(String.self, forKey: .statusCode)
        }
        
        self.startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        self.endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
    }
}

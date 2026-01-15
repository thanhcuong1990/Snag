import Foundation

public struct SnagLog: Codable, Sendable, Equatable, Hashable {
    public let timestamp: Date
    public let level: String
    public let message: String
    public let tag: String?
    public let details: [String: String]?
    
    public init(timestamp: Date = Date(), 
         level: String, 
         message: String, 
         tag: String? = nil, 
         details: [String: String]? = nil) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.tag = tag
        self.details = details
        
    }
}

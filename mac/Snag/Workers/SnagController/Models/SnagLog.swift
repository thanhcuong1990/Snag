import Foundation

struct SnagLog: Codable, Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    let timestamp: Date
    let level: String
    let message: String
    let tag: String?
    let details: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case timestamp, level, message, tag, details
    }
    
    init(timestamp: Date = Date(), 
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

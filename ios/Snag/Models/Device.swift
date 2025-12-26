import Foundation

public struct SnagDevice: Sendable {
    public var id: String?
    public var name: String?
    public var description: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "deviceId"
        case name = "deviceName"
        case description = "deviceDescription"
    }
}

extension SnagDevice: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
    }
}


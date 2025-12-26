import Foundation

public struct SnagProject: Sendable {
    public var name: String?
    
    enum CodingKeys: String, CodingKey {
        case name = "projectName"
    }
}

extension SnagProject: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
    }
}


import Foundation

public struct SnagPacket: Sendable {
    public var id: String?
    public var requestInfo: SnagRequestInfo?
    public var project: SnagProject?
    public var device: SnagDevice?
    
    enum CodingKeys: String, CodingKey {
        case id = "packetId"
        case requestInfo
        case project
        case device
    }
}

extension SnagPacket: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.requestInfo = try container.decodeIfPresent(SnagRequestInfo.self, forKey: .requestInfo)
        self.project = try container.decodeIfPresent(SnagProject.self, forKey: .project)
        self.device = try container.decodeIfPresent(SnagDevice.self, forKey: .device)
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(requestInfo, forKey: .requestInfo)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(device, forKey: .device)
    }
}


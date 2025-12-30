import Cocoa

class SnagPacket: Codable, Identifiable, Equatable, ObservableObject {
    var packetId: String?
    
    var id: String {
        return packetId ?? UUID().uuidString
    }
    
    @Published var requestInfo: SnagRequestInfo?
    
    var project: SnagProjectModel?
    var device: SnagDeviceModel?
    
    /// The time when this packet was first discovered/received by the Mac app.
    /// Initialized to Date() when the object is created (decoded).
    var discoveryDate: Date = Date()

    enum CodingKeys: String, CodingKey {
        case packetId
        case requestInfo
        case project
        case device
    }
    
    init() {
        self.discoveryDate = Date()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.packetId = try container.decodeIfPresent(String.self, forKey: .packetId)
        self.requestInfo = try container.decodeIfPresent(SnagRequestInfo.self, forKey: .requestInfo)
        self.project = try container.decodeIfPresent(SnagProjectModel.self, forKey: .project)
        self.device = try container.decodeIfPresent(SnagDeviceModel.self, forKey: .device)
        self.discoveryDate = Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packetId, forKey: .packetId)
        try container.encode(requestInfo, forKey: .requestInfo)
        try container.encode(project, forKey: .project)
        try container.encode(device, forKey: .device)
    }
    
    static func == (lhs: SnagPacket, rhs: SnagPacket) -> Bool {
        return lhs.packetId == rhs.packetId &&
               lhs.requestInfo?.statusCode == rhs.requestInfo?.statusCode &&
               lhs.requestInfo?.endDate == rhs.requestInfo?.endDate
    }
}



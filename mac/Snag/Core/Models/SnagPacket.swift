import Cocoa

class SnagPacket: Codable, Identifiable, Equatable, ObservableObject {
    var packetId: String?
    
    let id: String
    
    @Published var requestInfo: SnagRequestInfo?
    
    var project: SnagProjectModel?
    var device: SnagDeviceModel?
    var log: SnagLog?
    var control: SnagControl?
    
    /// The time when this packet was first discovered/received by the Mac app.
    /// Initialized to Date() when the object is created (decoded).
    var discoveryDate: Date = Date()
    
    /// Transient flag to indicate if this packet came from an unauthenticated connection.
    var isUnauthenticated: Bool = false

    enum CodingKeys: String, CodingKey {
        case packetId
        case requestInfo
        case project
        case device
        case log
        case control
    }
    
    init() {
        self.id = UUID().uuidString
        self.discoveryDate = Date()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pId = try container.decodeIfPresent(String.self, forKey: .packetId)
        self.packetId = pId
        self.id = pId ?? UUID().uuidString
        
        self.requestInfo = try container.decodeIfPresent(SnagRequestInfo.self, forKey: .requestInfo)
        self.project = try container.decodeIfPresent(SnagProjectModel.self, forKey: .project)
        self.device = try container.decodeIfPresent(SnagDeviceModel.self, forKey: .device)
        self.log = try container.decodeIfPresent(SnagLog.self, forKey: .log)
        self.control = try container.decodeIfPresent(SnagControl.self, forKey: .control)
        self.discoveryDate = Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packetId, forKey: .packetId)
        try container.encode(requestInfo, forKey: .requestInfo)
        try container.encode(project, forKey: .project)
        try container.encode(device, forKey: .device)
        try container.encode(log, forKey: .log)
        try container.encode(control, forKey: .control)
    }
    
    static func == (lhs: SnagPacket, rhs: SnagPacket) -> Bool {
        return lhs.packetId == rhs.packetId &&
               lhs.requestInfo?.statusCode == rhs.requestInfo?.statusCode &&
               lhs.requestInfo?.endDate == rhs.requestInfo?.endDate
    }
}



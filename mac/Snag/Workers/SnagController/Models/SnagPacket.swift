import Cocoa

class SnagPacket: Codable {
    var packetId: String?
    
    var requestInfo: SnagRequestInfo?
    
    var project: SnagProjectModel?
    var device: SnagDeviceModel?
    
}



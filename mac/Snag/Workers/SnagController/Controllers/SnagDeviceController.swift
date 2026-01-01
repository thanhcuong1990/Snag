import Cocoa

class SnagDeviceController: NSObject, ObservableObject {

    var deviceId: String?
    var deviceName: String?
    var deviceDescription: String?
    
    @Published var packets: [SnagPacket] = []
    @Published var logs: [SnagLog] = []
    
    @Published var isLogsPaused: Bool = true
    
    @Published private(set) var selectedPacket: SnagPacket?
    
    func select(packet: SnagPacket?) {
        self.selectedPacket = packet
        self.notifyPacketSelection()
    }
    
    func notifyPacketSelection() {
        NotificationCenter.default.post(name: SnagNotifications.didSelectPacket, object: nil)
    }
    
    @discardableResult
    func addPacket(newPacket: SnagPacket) -> Bool {
        
        if let log = newPacket.log {
            self.logs.append(log)
            return true
        }
        
        if newPacket.requestInfo == nil {
            return true
        }
        
        for packet in self.packets {
            
            if packet.packetId == newPacket.packetId {
                
                packet.requestInfo = newPacket.requestInfo
                return false
            }
        }
        
        self.packets.append(newPacket)
        
        
        
        if self.packets.count == 1 {
            
            self.selectedPacket = self.packets.first
        }
        
        return true
    }
    
    func clear() {
        
        self.packets.removeAll()
        self.logs.removeAll()
        self.select(packet: nil)
    }
}

import Cocoa

class SnagDeviceController: NSObject, ObservableObject {

    var deviceId: String?
    var deviceName: String?
    var deviceDescription: String?
    
    @Published var packets: [SnagPacket] = []
    @Published var logs: [SnagLog] = []
    
    @Published var isLogsPaused: Bool = false
    
    @Published private(set) var selectedPacket: SnagPacket?
    
    func select(packet: SnagPacket?) {
        self.selectedPacket = packet
        self.notifyPacketSelection()
    }
    
    func notifyPacketSelection() {
        NotificationCenter.default.post(name: SnagNotifications.didSelectPacket, object: nil)
    }
    
    private let maxItems = 2_000
    
    @discardableResult
    func addPacket(newPacket: SnagPacket) -> Bool {
        
        if let log = newPacket.log {
            // Always collect logs, even if paused (paused just means UI doesn't auto-scroll)
            self.logs.append(log)
            if self.logs.count > maxItems {
                self.logs.removeFirst()
            }
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
        if self.packets.count > maxItems {
            self.packets.removeFirst()
        }
        
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

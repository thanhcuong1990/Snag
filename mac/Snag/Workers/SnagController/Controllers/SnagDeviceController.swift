import Cocoa

class SnagDeviceController: NSObject, ObservableObject {

    var deviceId: String?
    var deviceName: String?
    var deviceDescription: String?
    
    @Published var packets: [SnagPacket] = []
    @Published var logs: [SnagLog] = []
    @Published var appInfo: SnagAppInfo?
    private var lastAppInfoRequest: Date = .distantPast
    
    @Published var isLogsPaused: Bool = true {
        didSet {
            self.sendStreamingControl()
        }
    }
    
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
        
        if self.deviceName == nil {
            self.deviceName = newPacket.device?.deviceName
        }
        if self.deviceDescription == nil {
            self.deviceDescription = newPacket.device?.deviceDescription
        }
        
        if self.appInfo == nil && newPacket.control == nil && Date().timeIntervalSince(lastAppInfoRequest) > 5.0 {
            self.requestAppInfo()
            self.lastAppInfoRequest = Date()
        }
        
        if let control = newPacket.control {
            self.handleControl(control)
            return true
        }
        
        if let log = newPacket.log {
            print("Snag: Log Received -> [\(log.tag)] \(log.message)")
            // Only collect logs if not paused
            if !self.isLogsPaused {
                self.logs.append(log)
                if self.logs.count > maxItems {
                    self.logs.removeFirst()
                }
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
    
    private func handleControl(_ control: SnagControl) {
        switch control.type {
        case "appInfoResponse":
            self.appInfo = control.appInfo
        case "logStreamingStatusRequest":
            self.sendStreamingControl()
            if self.appInfo == nil {
                self.requestAppInfo()
            }
        default:
            break
        }
    }
    
    func requestAppInfo() {
        var control = SnagControl(type: "appInfoRequest")
        self.sendControl(control)
    }
    
    private func sendStreamingControl() {
        let control = SnagControl(type: "logStreamingControl", shouldStreamLogs: !self.isLogsPaused)
        self.sendControl(control)
    }
    
    private func sendControl(_ control: SnagControl) {
        guard let deviceId = self.deviceId else { return }
        let packet = SnagPacket()
        packet.control = control
        // Optionally provide device/project info if needed by client
        SnagController.shared.publisher.send(packet: packet, toDeviceId: deviceId)
    }
}

import Cocoa

@MainActor
class SnagDeviceController: NSObject, ObservableObject {

    var deviceId: String?
    var deviceName: String?
    var deviceDescription: String?
    
    @Published var packets: [SnagPacket] = []
    @Published var logs: [SnagLog] = []
    @Published var appInfo: SnagAppInfo?
    @Published var hostName: String?
    @Published var ipAddress: String?
    private var lastAppInfoRequest: Date = .distantPast
    
    // Optimization: O(1) Lookup
    private var packetIds = Set<String>()
    
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
        if self.hostName == nil {
            self.hostName = newPacket.device?.hostName
        }
        if self.ipAddress == nil {
            self.ipAddress = newPacket.device?.ipAddress
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
        
        if let packetId = newPacket.packetId {
            if self.packetIds.contains(packetId) {
                // Update existing
                if let index = self.packets.firstIndex(where: { $0.packetId == packetId }) {
                    self.packets[index].requestInfo = newPacket.requestInfo
                    return false
                }
            }
        }
        
        self.packets.append(newPacket)
        if let packetId = newPacket.packetId {
            self.packetIds.insert(packetId)
        }
        
        if self.packets.count > maxItems {
            let removed = self.packets.removeFirst()
            if let removedId = removed.packetId {
                self.packetIds.remove(removedId)
            }
        }
        
        if self.packets.count == 1 {
            
            self.selectedPacket = self.packets.first
        }
        
        return true
    }
    
    func clear() {
        
        self.packets.removeAll()
        self.packetIds.removeAll()
        self.logs.removeAll()
        self.select(packet: nil)
    }
    
    private func handleControl(_ control: SnagControl) {
        switch control.type {
        case "appInfoResponse":
            if self.appInfo != control.appInfo {
                self.appInfo = control.appInfo
                // Notify parent project controller to propagate bundleId
                NotificationCenter.default.post(
                    name: SnagNotifications.didUpdateAppInfo,
                    object: self,
                    userInfo: ["bundleId": control.appInfo?.bundleId as Any]
                )
            }
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

        let control = SnagControl(type: "appInfoRequest")
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

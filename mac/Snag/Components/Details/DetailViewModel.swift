import Cocoa

class DetailViewModel: BaseViewModel {

    var packet: SnagPacket?
    
    func register() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.didUpdatePacket), name: SnagNotifications.didUpdatePacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshPacket), name: SnagNotifications.didSelectPacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshPacket), name: SnagNotifications.didSelectSavedPacket, object: nil)
        
        self.refreshPacket()
    }
    
    @objc func didUpdatePacket(notification: Notification) {
        if let packet = notification.userInfo?["packet"] as? SnagPacket {
            if packet.packetId == self.packet?.packetId {
                self.packet = packet
                self.onChange?()
            }
        }
    }
    
    @objc func refreshPacket() {
        if let project = SnagController.shared.selectedProjectController,
           let device = project.selectedDeviceController {
            self.packet = device.selectedPacket
        } else {
            // Fallback to saved packet if no remote project/device is selected
            self.packet = SnagController.shared.selectedSavedPacket
        }
        self.onChange?()
    }
}

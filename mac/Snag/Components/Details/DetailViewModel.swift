import Cocoa

class DetailViewModel: BaseViewModel {

    var packet: SnagPacket?
    
    func register() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.didUpdatePacket), name: SnagNotifications.didUpdatePacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshPacket), name: SnagNotifications.didSelectPacket, object: nil)
        
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
        self.packet = SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket
        self.onChange?()
    }
}

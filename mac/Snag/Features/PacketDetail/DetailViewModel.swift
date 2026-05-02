import Cocoa
import Combine

class DetailViewModel: BaseViewModel {

    var packet: SnagPacket?

    func register() {

        SnagController.shared.packetUpdatedPublisher
            .sink { [weak self] packet in
                self?.didUpdatePacket(packet)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshPacket), name: SnagNotifications.didSelectPacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshPacket), name: SnagNotifications.didSelectSavedPacket, object: nil)

        self.refreshPacket()
    }

    func didUpdatePacket(_ packet: SnagPacket) {
        if packet.packetId == self.packet?.packetId {
            self.packet = packet
            self.onChange?()
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

import Cocoa
import Combine

@MainActor
class DevicesViewModel: BaseListViewModel<SnagDeviceController>  {

    func register() {

        SnagController.shared.packetReceivedPublisher
            .sink { [weak self] _ in self?.refreshItems() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectProject, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectDevice, object: nil)

        self.refreshItems()
    }
    
    var selectedItem: SnagDeviceController? {
        
        return SnagController.shared.selectedProjectController?.selectedDeviceController
    }
    
    var selectedItemIndex: Int? {
        
        if let selectedItem = self.selectedItem {
            
            return self.items.firstIndex { $0 === selectedItem }
        }
        
        return nil
    }
    
    @objc func refreshItems() {
        
        self.set(items: SnagController.shared.selectedProjectController?.deviceControllers ?? [])
        self.onChange?()
    }
    
}

import Cocoa
import Combine

@MainActor
class ProjectsViewModel: BaseListViewModel<SnagProjectController> {

    func register() {

        SnagController.shared.packetReceivedPublisher
            .sink { [weak self] _ in self?.refreshItems() }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectProject, object: nil)

        self.refreshItems()
    }
    
    var selectedItem: SnagProjectController? {
        
        return SnagController.shared.selectedProjectController
    }
    
    var selectedItemIndex: Int? {
        
        if let selectedItem = self.selectedItem {
            
            return self.items.firstIndex { $0 === selectedItem }
        }
        
        return nil
    }
    
    @objc func refreshItems() {
        
        self.set(items: SnagController.shared.projectControllers) 
        self.onChange?()
    }
}

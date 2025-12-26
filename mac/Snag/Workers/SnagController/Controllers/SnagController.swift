import Cocoa


struct SnagNotifications {
    
    static let didGetPacket = NSNotification.Name("DidGetPacket")
    static let didUpdatePacket = NSNotification.Name("DidUpdatePacket")
    static let didSelectProject = NSNotification.Name("DidSelectProject")
    static let didSelectDevice = NSNotification.Name("DidSelectDevice")
    static let didSelectPacket = NSNotification.Name("DidSelectPacket")
}

class SnagController: NSObject, SnagPublisherDelegate, ObservableObject {
    
    static let shared = SnagController()
    
    @Published var projectControllers: [SnagProjectController] = []
    @Published var selectedProjectController: SnagProjectController? {
        didSet {
            NotificationCenter.default.post(name: SnagNotifications.didSelectProject, object: nil)
        }
    }
    
    var publisher = SnagPublisher()
    
    override init() {
        
        super.init()
        self.publisher.delegate = self
        self.publisher.startPublishing()
        
    }
    
    func didGetPacket(publisher: SnagPublisher, packet: SnagPacket) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.didGetPacket(publisher: publisher, packet: packet)
            }
            return
        }

        self.objectWillChange.send()

        if self.addPacket(newPacket: packet) {
            NotificationCenter.default.post(name: SnagNotifications.didGetPacket, object: nil, userInfo: ["packet": packet])
            self.checkInitialSelection()
        } else {
            NotificationCenter.default.post(name: SnagNotifications.didUpdatePacket, object: nil, userInfo: ["packet": packet])
        }
    }
    
    @discardableResult
    func addPacket(newPacket: SnagPacket) -> Bool {
        
        for projectController in self.projectControllers {
            
            if projectController.projectName == newPacket.project?.projectName {
                
                return projectController.addPacket(newPacket: newPacket)
            }
        }
        
        
        let projectController = SnagProjectController()
        
        projectController.projectName = newPacket.project?.projectName
        projectController.addPacket(newPacket: newPacket)
        
        self.projectControllers.append(projectController)
        
        
        
        if self.projectControllers.count == 1 {
            
            self.selectedProjectController = self.projectControllers.first
        }
        
        return true
    }
    
    
    func checkInitialSelection() {
        if self.selectedProjectController?.selectedDeviceController?.packets.count == 1 {
            self.selectedProjectController?.selectedDeviceController?.notifyPacketSelection()
        }
    }
}

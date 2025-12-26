import Cocoa

class SnagProjectController: NSObject, ObservableObject {
    
    @Published var projectName: String?
    @Published var appIcon: String?
    
    @Published var deviceControllers: [SnagDeviceController] = []
    @Published var selectedDeviceController: SnagDeviceController? {
        didSet {
            NotificationCenter.default.post(name: SnagNotifications.didSelectDevice, object: nil)
        }
    }
    
    @discardableResult
    func addPacket(newPacket: SnagPacket) -> Bool {
        
        if self.projectName == nil {
            self.projectName = newPacket.project?.projectName
        }
        
        if self.appIcon == nil {
            self.appIcon = newPacket.project?.appIcon
        }
        
        for deviceController in self.deviceControllers {
            
            if deviceController.deviceId == newPacket.device?.deviceId {
                
                return deviceController.addPacket(newPacket: newPacket)
            }
        }
        
        let deviceController = SnagDeviceController()
        
        deviceController.deviceId = newPacket.device?.deviceId
        deviceController.deviceName = newPacket.device?.deviceName
        deviceController.deviceDescription = newPacket.device?.deviceDescription
        
        deviceController.addPacket(newPacket: newPacket)
        
        self.deviceControllers.append(deviceController)
        
        if self.deviceControllers.count == 1 {
            
            self.selectedDeviceController = self.deviceControllers.first
        }
        
        return true
    }
}

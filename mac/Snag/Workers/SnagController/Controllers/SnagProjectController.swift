import Cocoa

@MainActor
class SnagProjectController: NSObject, ObservableObject {
    
    @Published var projectName: String?
    @Published var bundleId: String?
    @Published var appIcon: String?
    
    @Published var deviceControllers: [SnagDeviceController] = []
    @Published var selectedDeviceController: SnagDeviceController? {
        didSet {
            NotificationCenter.default.post(name: SnagNotifications.didSelectDevice, object: nil)
        }
    }
    
    private var observers: [Any] = []
    
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    @discardableResult
    func addPacket(newPacket: SnagPacket) -> Bool {
        
        if let newProjectName = newPacket.project?.projectName, self.projectName != newProjectName {
            self.projectName = newProjectName
        }
        
        if let newAppIcon = newPacket.project?.appIcon, self.appIcon != newAppIcon {
            self.appIcon = newAppIcon
        }
        
        if let newBundleId = newPacket.project?.bundleId, self.bundleId != newBundleId {
            self.bundleId = newBundleId
        }
        
        for deviceController in self.deviceControllers {
            
            if deviceController.deviceId == newPacket.device?.deviceId {
                
                let result = deviceController.addPacket(newPacket: newPacket)
                
                // Propagate bundleId from device appInfo if available
                if let appInfo = deviceController.appInfo, let newBundleId = appInfo.bundleId {
                    if self.bundleId != newBundleId {
                        self.bundleId = newBundleId
                    }
                }
                
                return result
            }
        }
        let deviceController = SnagDeviceController()
        deviceController.deviceId = newPacket.device?.deviceId
        
        deviceController.addPacket(newPacket: newPacket)
        
        // Observe appInfo updates from this device controller
        observeDeviceController(deviceController)
        
        self.deviceControllers.append(deviceController)
        
        if self.deviceControllers.count == 1 {
            DispatchQueue.main.async {
                self.selectedDeviceController = self.deviceControllers.first
            }
        }
        
        // Propagate bundleId from device appInfo if available
        if let appInfo = deviceController.appInfo, let newBundleId = appInfo.bundleId {
            if self.bundleId != newBundleId {
                self.bundleId = newBundleId
            }
        }
        
        return true
    }
    
    private func observeDeviceController(_ deviceController: SnagDeviceController) {
        let observer = NotificationCenter.default.addObserver(
            forName: SnagNotifications.didUpdateAppInfo,
            object: deviceController,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let bundleId = notification.userInfo?["bundleId"] as? String
            Task { @MainActor in
                if self.bundleId != bundleId {
                    self.bundleId = bundleId
                }
            }
        }
        observers.append(observer)
    }
}

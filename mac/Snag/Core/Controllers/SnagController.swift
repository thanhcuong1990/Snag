import Cocoa


struct SnagNotifications {
    
    static let didGetPacket = NSNotification.Name("DidGetPacket")
    static let didUpdatePacket = NSNotification.Name("DidUpdatePacket")
    static let didSelectProject = NSNotification.Name("DidSelectProject")
    static let didSelectDevice = NSNotification.Name("DidSelectDevice")
    static let didSelectPacket = NSNotification.Name("DidSelectPacket")
    static let didSelectSavedPacket = NSNotification.Name("DidSelectSavedPacket") // New notification for saved packets
    static let didUpdateSavedPackets = NSNotification.Name("DidUpdateSavedPackets") // New notification for list updates
    static let didUpdateAppInfo = NSNotification.Name("DidUpdateAppInfo") // For bundleId propagation
}

@MainActor
class SnagController: NSObject, @MainActor SnagPublisherDelegate, ObservableObject {
    
    static let shared = SnagController()
    
    enum MainTab {
        case network
        case logs
    }
    
    @Published var selectedTab: MainTab = .network {
        didSet {
            DispatchQueue.main.async {
                self.updateLogStreamingState()
            }
        }
    }
    @Published var projectControllers: [SnagProjectController] = []
    @Published var selectedProjectController: SnagProjectController? {
        didSet {
            NotificationCenter.default.post(name: SnagNotifications.didSelectProject, object: nil)
            DispatchQueue.main.async {
                self.updateLogStreamingState()
            }
        }
    }
    // New property for saved request selection
    @Published var selectedSavedPacket: SnagPacket? {
        didSet {
            NotificationCenter.default.post(name: SnagNotifications.didSelectSavedPacket, object: nil)
        }
    }
    
    @Published var publisherStatus: String = "Stopped"
    @Published var isSecurityEnabled: Bool = SnagConfiguration.isSecurityEnabled
    @Published var securityPIN: String = SnagConfiguration.securityPIN ?? ""
    
    var publisher = SnagPublisher()
    
    override init() {
        
        super.init()
        self.publisher.delegate = self
        self.publisher.startPublishing()
        self.publisherStatus = "Starting..."
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceSelection), name: SnagNotifications.didSelectDevice, object: nil)
        
        // Observe Force PIN setting change to restart listener if needed (or just disconnect clients to force re-auth)
        // Since SettingsManager is a singleton and might not emit KVO nicely, we might need to check how SidebarView updates it.
        // SidebarView uses a Binding to SettingsManager.shared.forceInteractiveAuth.
        // We can add a notification or just observe it if SettingsManager supports it.
        // For now, assuming SettingsManager doesn't post notifications, we'll patch SettingsManager or SidebarView?
        // Actually, let's just make SnagController observe a custom notification we'll verify.
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsChange), name: NSNotification.Name("SnagSettingsChanged"), object: nil)
    }
    
    @objc private func handleSettingsChange() {
        // Restart publishing or just disconnect all to force re-handshake
        print("SnagController: Settings changed. Restarting publisher to apply new security policy.")
        self.publisherStatus = "Restarting..."
        self.publisher.stopPublishing() // We need to expose stopPublishing or add restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
             self.publisher.startPublishing()
        }
    }
    
    @objc private func handleDeviceSelection() {
        self.updateLogStreamingState()
    }
    
    private func updateLogStreamingState() {
        for project in self.projectControllers {
            for device in project.deviceControllers {
                let isSelected = (project == self.selectedProjectController) && (device == project.selectedDeviceController)
                let shouldStream = isSelected && (self.selectedTab == .logs)
                
                // Update isLogsPaused state only if it differs from the desired state
                // isLogsPaused needs to be false if streaming is desired
                if device.isLogsPaused == shouldStream {
                    device.isLogsPaused = !shouldStream
                }
            }
        }
    }
    
    func didGetPacket(publisher: SnagPublisher, packet: SnagPacket) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.didGetPacket(publisher: publisher, packet: packet)
            }
            return
        }

        // self.objectWillChange.send()

        if self.addPacket(newPacket: packet) {
            NotificationCenter.default.post(name: SnagNotifications.didGetPacket, object: nil, userInfo: ["packet": packet])
            self.checkInitialSelection()
        } else {
            NotificationCenter.default.post(name: SnagNotifications.didUpdatePacket, object: nil, userInfo: ["packet": packet])
        }
        
        // Ensure log streaming state is correct for new devices
        if packet.device != nil {
             DispatchQueue.main.async {
                 self.updateLogStreamingState()
             }
        }
    }
    
    @discardableResult
    func addPacket(newPacket: SnagPacket) -> Bool {
        
        // 1. Prioritize finding an existing device controller across all projects
        // Handshake packets (auth_required) often miss project info, but contain DeviceID.
        // We should route them to the *existing* device/project if known.
        let deviceId = (newPacket.device?.deviceId ?? newPacket.control?.deviceId)?.lowercased()
        
        if let id = deviceId {
            for projectController in self.projectControllers {
                // 1a. Direct Device ID Match (Prioritize this above all else)
                if let existingDeviceController = projectController.deviceControllers.first(where: { $0.deviceId == id }) {
                    // Force update device metadata if it's currently missing or generic
                    if let deviceModel = newPacket.device {
                        if existingDeviceController.deviceName == nil || existingDeviceController.deviceName == "Unknown Device" {
                            existingDeviceController.deviceName = deviceModel.deviceName
                        }
                        if existingDeviceController.deviceDescription == nil {
                            existingDeviceController.deviceDescription = deviceModel.deviceDescription
                        }
                    }
                    
                    // Update project name and app icon if they are currently "Unknown" or nil
                    if let newProjectName = newPacket.project?.projectName,
                       (projectController.projectName == nil || projectController.projectName == "Unknown" || projectController.projectName != newProjectName) {
                        projectController.projectName = newProjectName
                    }
                    
                    if let newAppIcon = newPacket.project?.appIcon, (projectController.appIcon == nil || projectController.appIcon != newAppIcon) {
                        projectController.appIcon = newAppIcon
                    }
                    
                    return projectController.addPacket(newPacket: newPacket)
                }
            }
        }
        
        // 2. Fallback to Bundle ID matching
        if let newBundleId = newPacket.project?.bundleId {
            for projectController in self.projectControllers {
                if projectController.bundleId == newBundleId {
                    // Update project name and app icon if they are currently "Unknown" or nil
                    if let newProjectName = newPacket.project?.projectName,
                       (projectController.projectName == nil || projectController.projectName == "Unknown" || projectController.projectName != newProjectName) {
                        projectController.projectName = newProjectName
                    }
                    
                    if let newAppIcon = newPacket.project?.appIcon, (projectController.appIcon == nil || projectController.appIcon != newAppIcon) {
                        projectController.appIcon = newAppIcon
                    }
                    return projectController.addPacket(newPacket: newPacket)
                }
            }
        }
        
        // 3. Fallback to Project Name matching
        for projectController in self.projectControllers {
            if projectController.projectName == newPacket.project?.projectName {
                // Only match by name if the project doesn't have a different bundleId already
                if projectController.bundleId == nil || projectController.bundleId == newPacket.project?.bundleId {
                    return projectController.addPacket(newPacket: newPacket)
                }
            }
        }
        
        // 4. Create New Project Controller
        let projectController = SnagProjectController()
        projectController.projectName = newPacket.project?.projectName
        projectController.addPacket(newPacket: newPacket)
        
        self.projectControllers.append(projectController)
        
        if self.projectControllers.count == 1 {
            DispatchQueue.main.async {
                self.selectedProjectController = self.projectControllers.first
            }
        }
        
        return true
    }
    
    
    func checkInitialSelection() {
        if self.selectedProjectController?.selectedDeviceController?.packets.count == 1 {
            self.selectedProjectController?.selectedDeviceController?.notifyPacketSelection()
        }
    }
    
    // Unified Accessor for Current Packet (Live or Saved)
    var currentSelectedPacket: SnagPacket? {
        if let project = selectedProjectController,
           let device = project.selectedDeviceController {
            return device.selectedPacket
        } else {
            return selectedSavedPacket
        }
    }
    
    func authorizeDevice(_ deviceController: SnagDeviceController, enteredPIN: String) -> Bool {
        guard let deviceId = deviceController.deviceId else { return false }
        
        // Verification happens in the Publisher via Crypto
        if publisher.authorizeDevice(deviceId: deviceId, pin: enteredPIN) {
            // Refresh the device state
            deviceController.isAuthenticated = true
            deviceController.requestAppInfo()
            return true
        }
        
        return false
    }
    
    func isDeviceLocked(deviceId: String) -> (locked: Bool, remainingSeconds: Int?) {
        return publisher.getLockoutStatus(deviceId: deviceId)
    }
}

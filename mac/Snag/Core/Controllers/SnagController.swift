import Cocoa
import Combine


struct SnagNotifications {

    static let didSelectProject = NSNotification.Name("DidSelectProject")
    static let didSelectDevice = NSNotification.Name("DidSelectDevice")
    static let didSelectPacket = NSNotification.Name("DidSelectPacket")
    static let didSelectSavedPacket = NSNotification.Name("DidSelectSavedPacket") // New notification for saved packets
    static let didUpdateSavedPackets = NSNotification.Name("DidUpdateSavedPackets") // New notification for list updates
    static let didUpdateAppInfo = NSNotification.Name("DidUpdateAppInfo") // For bundleId propagation
    // Composer
    static let didOpenDraft = NSNotification.Name("DidOpenDraft")
    static let didCloseDraft = NSNotification.Name("DidCloseDraft")
    static let didUpdateDrafts = NSNotification.Name("DidUpdateDrafts")
    static let didFinishDraftRun = NSNotification.Name("DidFinishDraftRun")
}

@MainActor
class SnagController: NSObject, @MainActor SnagPublisherDelegate, ObservableObject {
    
    static let shared = SnagController()

    @Published var route: MainContentRoute = .network {
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

    let packetReceivedPublisher = PassthroughSubject<SnagPacket, Never>()
    let packetUpdatedPublisher = PassthroughSubject<SnagPacket, Never>()

    // Fast O(1) lookup for the hot per-packet path.
    private var deviceIndex: [String: (project: SnagProjectController, device: SnagDeviceController)] = [:]

    var publisher = SnagPublisher()
    
    override init() {
        
        super.init()
        self.publisher.delegate = self
        self.publisher.startPublishing()
        self.publisherStatus = "Starting..."
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceSelection), name: SnagNotifications.didSelectDevice, object: nil)
    }
    
    @objc private func handleDeviceSelection() {
        self.updateLogStreamingState()
    }
    
    private func updateLogStreamingState() {
        for project in self.projectControllers {
            for device in project.deviceControllers {
                let isSelected = (project == self.selectedProjectController) && (device == project.selectedDeviceController)
                let shouldStream = isSelected && (self.route == .logs)

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
            self.packetReceivedPublisher.send(packet)
            self.checkInitialSelection()
        } else {
            self.packetUpdatedPublisher.send(packet)
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

        // 1. Prioritize finding an existing device controller across all projects.
        let deviceId = (newPacket.device?.deviceId ?? newPacket.control?.deviceId)?.lowercased()

        // 1a. Direct Device ID Match via O(1) dictionary lookup.
        if let id = deviceId, let entry = deviceIndex[id] {
            let projectController = entry.project
            let existingDeviceController = entry.device

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

        // 2. Fallback to Bundle ID matching (project count is small)
        var matchedProject: SnagProjectController?
        if let newBundleId = newPacket.project?.bundleId {
            for projectController in self.projectControllers where projectController.bundleId == newBundleId {
                // Update project name and app icon if they are currently "Unknown" or nil
                if let newProjectName = newPacket.project?.projectName,
                   (projectController.projectName == nil || projectController.projectName == "Unknown" || projectController.projectName != newProjectName) {
                    projectController.projectName = newProjectName
                }

                if let newAppIcon = newPacket.project?.appIcon, (projectController.appIcon == nil || projectController.appIcon != newAppIcon) {
                    projectController.appIcon = newAppIcon
                }
                matchedProject = projectController
                break
            }
        }

        // 3. Fallback to Project Name matching
        if matchedProject == nil {
            for projectController in self.projectControllers {
                if projectController.projectName == newPacket.project?.projectName,
                   projectController.bundleId == nil || projectController.bundleId == newPacket.project?.bundleId {
                    matchedProject = projectController
                    break
                }
            }
        }

        let projectController: SnagProjectController
        let isNewProject: Bool
        if let existing = matchedProject {
            projectController = existing
            isNewProject = false
        } else {
            // 4. Create New Project Controller
            projectController = SnagProjectController()
            projectController.projectName = (newPacket.project?.projectName == nil || newPacket.project?.projectName?.isEmpty == true) ? "Unknown" : newPacket.project?.projectName
            isNewProject = true
        }

        let result = projectController.addPacket(newPacket: newPacket)

        if isNewProject {
            self.projectControllers.append(projectController)
            if self.projectControllers.count == 1 {
                DispatchQueue.main.async {
                    self.selectedProjectController = self.projectControllers.first
                }
            }
        }

        // Register the (possibly new) device in the index for future O(1) lookups.
        if let id = deviceId, deviceIndex[id] == nil,
           let device = projectController.deviceControllers.first(where: { $0.deviceId == id }) {
            deviceIndex[id] = (projectController, device)
        }

        return result
    }
    
    
    func checkInitialSelection() {
        if self.selectedProjectController?.selectedDeviceController?.packets.count == 1 {
            self.selectedProjectController?.selectedDeviceController?.notifyPacketSelection()
        }
    }
    
    // MARK: - Route helpers

    func selectProject(_ project: SnagProjectController?) {
        self.selectedProjectController = project
        if self.route == .saved || self.route == .compose {
            self.route = .network
        }
    }

    func selectSaved() {
        self.selectedProjectController = nil
        self.route = .saved
    }

    func selectCompose() {
        self.route = .compose
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
    
}

import Cocoa

class LogsViewModel: ObservableObject {
    
    @Published var items: [SnagLog] = []
    @Published var filterTerm: String = "" {
        didSet {
            self.reloadLogs()
        }
    }
    
    private var isUpdatePending = false
    private let updateRateLimit: TimeInterval = 0.2 // 200ms throttle
    
    var isPaused: Bool {
        get {
            return SnagController.shared.selectedProjectController?.selectedDeviceController?.isLogsPaused ?? true
        }
        set {
            SnagController.shared.selectedProjectController?.selectedDeviceController?.isLogsPaused = newValue
        }
    }
    
    func togglePause() {
        self.isPaused.toggle()
        self.objectWillChange.send()
        
        if !self.isPaused {
            self.reloadLogs()
        }
    } 
    
    private var allLogs: [SnagLog] {
        return SnagController.shared.selectedProjectController?.selectedDeviceController?.logs ?? []
    }
    
    func register() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.onPacketReceived), name: SnagNotifications.didGetPacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onDeviceChanged), name: SnagNotifications.didSelectProject, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onDeviceChanged), name: SnagNotifications.didSelectDevice, object: nil)
        
        self.reloadLogs()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func onPacketReceived() {
        if isPaused { return }
        self.reloadLogs()
    }
    
    @objc func onDeviceChanged() {
        self.reloadLogs()
    }
    private var lastUpdate: Date = .distantPast
    
    func reloadLogs() {
        if isPaused { return }
        if isUpdatePending { return }
        
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastUpdate)
        
        if timeSinceLast >= updateRateLimit {
            // Update immediately
            self.performUpdate()
            self.lastUpdate = Date()
        } else {
            // Schedule for later (at the end of the window)
            isUpdatePending = true
            let delay = updateRateLimit - timeSinceLast
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.isUpdatePending = false
                self.performUpdate()
                self.lastUpdate = Date()
            }
        }
    }
    
    private func performUpdate() {
        let logs = self.allLogs
        let term = self.filterTerm.lowercased()
        
        let filtered = logs.filter { log in
            if term.isEmpty { return true }
            return log.message.lowercased().contains(term) ||
            log.tag?.lowercased().contains(term) ?? false ||
            log.level.lowercased().contains(term)
        }
        
        DispatchQueue.main.async {
            self.items = filtered.reversed()
        }
    }
    
    func clearLogs() {
        SnagController.shared.selectedProjectController?.selectedDeviceController?.clear()
        self.items = []
    }
}

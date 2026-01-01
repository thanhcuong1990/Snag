import Cocoa

class LogsViewModel: ObservableObject {
    
    @Published var items: [SnagLog] = []
    @Published var filterTerm: String = "" {
        didSet {
            self.refreshItems()
        }
    }
    
    // Simple enum for log level filtering if needed later
    // var levelFilter: String? 
    
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
    
    @objc func onPacketReceived() {
        if isPaused { return }
        self.reloadLogs()
    }
    
    @objc func onDeviceChanged() {
        // Force reload when device changes to show the selected device's logs
        // but respect pause state - show current snapshot, no future updates
        self.forceReloadLogs()
    }
    
    // Formerly refreshItems
    func refreshItems() {
        self.reloadLogs()
    }
    
    /// Force reload logs regardless of pause state (used for device switching)
    private func forceReloadLogs() {
        let logs = self.allLogs
        
        guard !filterTerm.isEmpty else {
            self.items = logs
            return
        }
        
        let term = filterTerm.lowercased()
        self.items = logs.filter { log in
            log.message.lowercased().contains(term) ||
            log.tag?.lowercased().contains(term) ?? false ||
            log.level.lowercased().contains(term)
        }
    }
    
    func reloadLogs() {
        // Don't reload if paused
        if isPaused { return }
        
        let logs = self.allLogs
        
        guard !filterTerm.isEmpty else {
            self.items = logs
            return
        }
        
        let term = filterTerm.lowercased()
        self.items = logs.filter { log in
            log.message.lowercased().contains(term) ||
            log.tag?.lowercased().contains(term) ?? false ||
            log.level.lowercased().contains(term)
        }
    }
    
    func clearLogs() {
        SnagController.shared.selectedProjectController?.selectedDeviceController?.clear()
        // Force clear items even if paused
        self.items = []
    }
}

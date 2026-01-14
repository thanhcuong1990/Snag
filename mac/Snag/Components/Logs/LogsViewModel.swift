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
    
    @Published var selectedTag: String? = nil {
        didSet {
            self.reloadLogs()
        }
    }
    @Published var tags: [String] = []

    private func isSystemTag(_ tag: String) -> Bool {
        if tag.isEmpty || tag == "System" { return true }
        if tag.starts(with: "com.apple.") || tag.starts(with: "com.google.") || tag.starts(with: "com.android.") {
            return true
        }
        
        // Match common prefixes for system/chromium/view processes
        if tag.starts(with: "cr_") || tag.starts(with: "VRI[") || tag.starts(with: "Netd") || tag.starts(with: "Compatibility") {
            return true
        }
        
        let androidSystemTags: Set<String> = [
            "ApplicationLoaders", "HWUI", "ProfileInstaller", "chromium",
            "Choreographer", "ActivityThread", "ViewRootImpl", "WindowManager",
            "InputMethodManager", "AudioTrack", "OpenGLRenderer", "vndksupport",
            "logcat", "ServiceManager", "System.out", "System.err",
            "DesktopExperienceFlags", "DesktopModeFlags", "GFXSTREAM",
            "GraphicsEnvironment", "ImeTracker", "InsetsController",
            "ResourcesManager", "SoLoader", "WebViewFactory",
            "WindowOnBackDispatcher", "Zygote", "ashmem",
            "jni_lib_merge", "nativeloader", "unknown", "Process",
            "StudioAgent", "TransportManager"
        ]
        return androidSystemTags.contains(tag)
    }

    enum LogFilterLevel: String, CaseIterable {
        case all = "All"
        case error = "Error"
        case warning = "Warning"
        case info = "Info"
        case debug = "Debug"
        
        var localizedName: String {
            return self.rawValue.localized
        }
    }
    
    @Published var selectedLogLevel: LogFilterLevel = .all {
        didSet {
            self.reloadLogs()
        }
    }

    private func performUpdate() {
        let logs = self.allLogs
        let term = self.filterTerm.lowercased()
        
        // Extract tags with grouping
        let rawTags = logs.compactMap { $0.tag }
        var uniqueTags = Set<String>()
        
        for tag in rawTags {
            if tag == "React Native" || tag.starts(with: "com.facebook.react.log") {
                uniqueTags.insert("React Native")
            } else if isSystemTag(tag) {
                uniqueTags.insert("System")
            } else {
                uniqueTags.insert(tag)
            }
        }
        
        // Sort tags: React Native first, System second, then others alphabetically
        let allTags = uniqueTags.sorted { t1, t2 in
            if t1 == "React Native" { return true }
            if t2 == "React Native" { return false }
            if t1 == "System" { return true }
            if t2 == "System" { return false }
            return t1 < t2
        }
        
        let filtered = logs.filter { log in
            // Filter by Level
            if self.selectedLogLevel != .all {
                let level = log.level.lowercased()
                switch self.selectedLogLevel {
                case .error:
                    if !level.contains("error") && !level.contains("fault") { return false }
                case .warning:
                    if !level.contains("warn") { return false }
                case .info:
                    if !level.contains("info") { return false }
                case .debug:
                    if !level.contains("debug") { return false }
                default: break
                }
            }
            
            // Filter by Tag
            if let selected = selectedTag {
                let logTag = log.tag ?? ""
                if selected == "System" {
                     if !isSystemTag(logTag) {
                         return false
                     }
                } else if selected == "React Native" {
                    if !logTag.starts(with: "com.facebook.react.log") && logTag != "React Native" {
                        return false
                    }
                } else if logTag != selected {
                    return false
                }
            }
            
            // Filter by Search Term
            if term.isEmpty { return true }
            return log.message.lowercased().contains(term) ||
            log.tag?.lowercased().contains(term) ?? false ||
            log.level.lowercased().contains(term)
        }
        
        DispatchQueue.main.async {
            self.tags = allTags
            self.items = filtered.reversed()
        }
    }
    
    func clearLogs() {
        SnagController.shared.selectedProjectController?.selectedDeviceController?.clear()
        self.items = []
    }
}

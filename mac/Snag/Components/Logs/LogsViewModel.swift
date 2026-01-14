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
    private let processingQueue = DispatchQueue(label: "com.snag.logs.processing", qos: .userInteractive)
    private let displayLimit = 1000
    
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
    
    @objc func onPacketReceived(_ notification: Notification) {
        if isPaused { return }
        
        // Streaming Optimization: Check if we can ignore this packet based on current filter
        if let selected = selectedTag, let packet = notification.userInfo?["packet"] as? SnagPacket, let log = packet.log {
            let logTag = log.tag ?? ""
            if selected == "System" {
                if !isSystemTag(logTag) { return }
            } else if selected == "React Native" {
                if !logTag.starts(with: "com.facebook.react.log") && logTag != "React Native" { return }
            } else if selected == "App" {
                // "App" logic will match the identified main tag
                if let appTag = self.detectedAppTag, logTag != appTag { return }
            } else if logTag != selected {
                return
            }
        }
        
        self.reloadLogs()
    }
    
    @objc func onDeviceChanged() {
        self.objectWillChange.send()
        self.reloadLogs(force: true)
    }
    private var lastUpdate: Date = .distantPast
    
    func reloadLogs(force: Bool = false) {
        if !force && isPaused { return }
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
            // Auto-unpause if selecting a non-React Native tag that requires streaming
            if let selected = selectedTag, selected == "System" || selected == "App" {
                self.isPaused = false
            }
            self.reloadLogs()
        }
    }
    @Published var tags: [String] = []
    private var detectedAppTag: String? = nil

    private func isSystemTag(_ tag: String) -> Bool {
        if tag.isEmpty || tag == "System" || tag == "logcat" || tag == "unknown" { return true }
        
        let lowerTag = tag.lowercased()
        
        // Match common system prefixes/patterns
        if lowerTag.starts(with: "android.") || 
           lowerTag.starts(with: "com.android.") ||
           lowerTag.starts(with: "com.google.") ||
           lowerTag.starts(with: "com.apple.") ||
           lowerTag.starts(with: "libc") ||
           lowerTag.starts(with: "art") ||
           lowerTag.starts(with: "gralloc") ||
           lowerTag.starts(with: "egl_") ||
           lowerTag.contains("emulator") ||
           lowerTag.contains("vulkan") {
            return true
        }
        
        // Match specific patterns often seen in logs
        if tag.starts(with: "cr_") || tag.starts(with: "VRI[") || tag.starts(with: "Netd") || tag.contains("Compatibility") {
            return true
        }
        
        let androidSystemTags: Set<String> = [
            "ApplicationLoaders", "HWUI", "ProfileInstaller", "chromium",
            "Choreographer", "ActivityThread", "ViewRootImpl", "WindowManager",
            "InputMethodManager", "AudioTrack", "OpenGLRenderer", "vndksupport",
            "ServiceManager", "System.out", "System.err",
            "DesktopExperienceFlags", "DesktopModeFlags", "GFXSTREAM",
            "GraphicsEnvironment", "ImeTracker", "InsetsController",
            "ResourcesManager", "SoLoader", "WebViewFactory",
            "WindowOnBackDispatcher", "Zygote", "ashmem",
            "jni_lib_merge", "nativeloader", "Process",
            "StudioAgent", "TransportManager", "SurfaceControl",
            "SurfaceFlavor", "InputTransport", "HostConnection",
            "FrameEvents", "Chatty", "TetheringManager", "BatteryService"
        ]
        return androidSystemTags.contains(tag) || androidSystemTags.contains(lowerTag)
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
        let selectedLevel = self.selectedLogLevel
        let selectedTag = self.selectedTag
        
        let deviceController = SnagController.shared.selectedProjectController?.selectedDeviceController
        let appInfo = deviceController?.appInfo
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Extract and Analyze Tags
            var tagCounts: [String: Int] = [:]
            var uniqueTags = Set<String>()
            
            for log in logs {
                if let tag = log.tag {
                    let isRNLog = tag.starts(with: "com.facebook.react.log") || tag == "React Native"
                    let isBundleLog = appInfo?.bundleId != nil && tag == appInfo?.bundleId
                    
                    if isRNLog {
                        uniqueTags.insert("React Native")
                    } else if isBundleLog {
                        uniqueTags.insert("App")
                        tagCounts[tag, default: 0] += 1
                    } else if self.isSystemTag(tag) {
                        uniqueTags.insert("System")
                    } else {
                        uniqueTags.insert(tag)
                        tagCounts[tag, default: 0] += 1
                    }
                }
            }
            
            // Identify "App" tag (explicit bundleId or most frequent non-system non-RN tag)
            let detectedAppTag = appInfo?.bundleId ?? tagCounts.max(by: { $0.value < $1.value })?.key
            if detectedAppTag != nil { uniqueTags.insert("App") }
            
            // Sort tags: React Native first, System second, App third, then others alphabetically
            let sortedTags = uniqueTags.sorted { t1, t2 in
                let priority: [String: Int] = ["React Native": 0, "System": 1, "App": 2]
                let p1 = priority[t1] ?? 100
                let p2 = priority[t2] ?? 100
                if p1 != p2 { return p1 < p2 }
                return t1 < t2
            }
            
            // 2. Filter Logs
            let filtered = logs.filter { log in
                // Filter by Level
                if selectedLevel != .all {
                    let level = log.level.lowercased()
                    switch selectedLevel {
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
                         if !self.isSystemTag(logTag) { return false }
                    } else if selected == "React Native" {
                        if !logTag.starts(with: "com.facebook.react.log") && logTag != "React Native" { return false }
                    } else if selected == "App" {
                        if logTag != detectedAppTag { return false }
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
            
            // 3. Limit Results for Display
            let itemsToDisplay = Array(filtered.reversed().prefix(self.displayLimit))
            
            DispatchQueue.main.async {
                self.detectedAppTag = detectedAppTag
                self.tags = sortedTags
                self.items = itemsToDisplay
            }
        }
    }
    
    func clearLogs() {
        SnagController.shared.selectedProjectController?.selectedDeviceController?.clear()
        self.items = []
    }
}

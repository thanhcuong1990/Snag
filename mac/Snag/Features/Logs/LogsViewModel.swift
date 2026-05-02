import Cocoa
import Combine

@MainActor
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
    private var cancellables = Set<AnyCancellable>()

    // Cached tag analysis. Tags depend only on the log set, not on the active filter,
    // so we can reuse them across keystrokes. Keyed on log count + bundleId as a cheap
    // change-detection heuristic.
    private struct TagAnalysisCache {
        let logCount: Int
        let bundleId: String?
        let sortedTags: [String]
        let detectedAppTag: String?
    }
    private var tagAnalysisCache: TagAnalysisCache?
    
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
    
    func resume() {
        self.isPaused = false
        self.objectWillChange.send()
        self.reloadLogs()
    }
    
    private var allLogs: [SnagLog] {
        return SnagController.shared.selectedProjectController?.selectedDeviceController?.logs ?? []
    }
    
    func register() {
        SnagController.shared.packetReceivedPublisher
            .sink { [weak self] packet in self?.onPacketReceived(packet) }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onDeviceChanged), name: SnagNotifications.didSelectProject, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.onDeviceChanged), name: SnagNotifications.didSelectDevice, object: nil)

        self.reloadLogs()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func onPacketReceived(_ packet: SnagPacket) {
        if isPaused { return }

        // Streaming Optimization: Check if we can ignore this packet based on current filter
        if let selected = selectedTag, let log = packet.log {
            let logTag = log.tag ?? ""
            if selected == "System" {
                if !SnagLog.isSystemTag(logTag) { return }
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
        self.isPaused = false // Auto-resume on device change
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
        let bundleId = appInfo?.bundleId
        let cachedAnalysis = self.tagAnalysisCache

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. Extract and Analyze Tags (reuse cache when log set is stable)
            let sortedTags: [String]
            let detectedAppTag: String?

            if let cache = cachedAnalysis,
               cache.logCount == logs.count,
               cache.bundleId == bundleId {
                sortedTags = cache.sortedTags
                detectedAppTag = cache.detectedAppTag
            } else {
                var tagCounts: [String: Int] = [:]
                var uniqueTags = Set<String>()

                for log in logs {
                    let category = log.getCategory(detectedAppTag: bundleId)

                    switch category {
                    case .rn:
                        uniqueTags.insert("React Native")
                    case .app:
                        uniqueTags.insert("App")
                        if let tag = log.tag { tagCounts[tag, default: 0] += 1 }
                    case .system:
                        uniqueTags.insert("System")
                    case .other:
                        if let tag = log.tag {
                            uniqueTags.insert(tag)
                            tagCounts[tag, default: 0] += 1
                        }
                    }
                }

                // Identify "App" tag (explicit bundleId or most frequent non-system non-RN tag)
                let computedAppTag = bundleId ?? tagCounts.max(by: { $0.value < $1.value })?.key
                if computedAppTag != nil { uniqueTags.insert("App") }

                // Sort tags: React Native first, System second, App third, then others alphabetically
                let priority: [String: Int] = ["React Native": 0, "System": 1, "App": 2]
                let computedSorted = uniqueTags.sorted { t1, t2 in
                    let p1 = priority[t1] ?? 100
                    let p2 = priority[t2] ?? 100
                    if p1 != p2 { return p1 < p2 }
                    return t1 < t2
                }

                sortedTags = computedSorted
                detectedAppTag = computedAppTag
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
                    let category = log.getCategory(detectedAppTag: bundleId)

                    if selected == "System" {
                        if category != .system { return false }
                    } else if selected == "React Native" {
                        if category != .rn { return false }
                    } else if selected == "App" {
                        if category != .app { return false }
                    } else if log.tag != selected {
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

            let newCache = TagAnalysisCache(
                logCount: logs.count,
                bundleId: bundleId,
                sortedTags: sortedTags,
                detectedAppTag: detectedAppTag
            )

            DispatchQueue.main.async {
                self.tagAnalysisCache = newCache
                self.detectedAppTag = detectedAppTag
                self.tags = sortedTags
                self.items = itemsToDisplay
            }
        }
    }
    
    func clearLogs() {
        SnagController.shared.selectedProjectController?.selectedDeviceController?.clear()
        self.tagAnalysisCache = nil
        self.items = []
    }
}

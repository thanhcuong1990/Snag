import Cocoa

enum PacketFilterCategory: String, CaseIterable {
    case all = "All"
    case fetchXHR = "Fetch/XHR"
    case media = "Media"
    case status1xx = "1xx"
    case status2xx = "2xx"
    case status3xx = "3xx"
    case status4xx = "4xx"
    case status5xx = "5xx"
    
    var localizedName: String {
        return self.rawValue.localized
    }
}

@MainActor
class PacketsViewModel: BaseListViewModel<SnagPacket>  {
    
    // MARK: - Debouncing for Performance
    private var isUpdatePending = false
    private var lastUpdate: Date = .distantPast
    private let updateRateLimit: TimeInterval = 0.15 // 150ms throttle
    
    private static let mediaPathExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "svg", "ico",
        "mp4", "m4v", "mov", "webm", "mkv", "avi", "mpeg", "mpg", "m3u8", "ts",
        "mp3", "m4a", "aac", "wav", "ogg", "oga", "flac", "opus"
    ]
    
    private static let nonFetchAssetPathExtensions: Set<String> = [
        "js", "mjs", "css",
        "woff", "woff2", "ttf", "otf", "eot",
        "map",
        "json",
        "pdf"
    ]
    
    private func urlPathExtension(_ urlString: String?) -> String? {
        guard var s = urlString?.lowercased(), !s.isEmpty else { return nil }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        if let h = s.firstIndex(of: "#") { s = String(s[..<h]) }
        if let slash = s.lastIndex(of: "/") { s = String(s[s.index(after: slash)...]) }
        guard let dot = s.lastIndex(of: "."), dot < s.index(before: s.endIndex) else { return nil }
        return String(s[s.index(after: dot)...])
    }
    
    private func isMediaPacket(_ packet: SnagPacket) -> Bool {
        if let contentType = packet.requestInfo?.responseContentType?.lowercased() {
            return contentType.contains("image") || contentType.contains("video") || contentType.contains("audio")
        }
        if let ext = urlPathExtension(packet.requestInfo?.url) {
            return Self.mediaPathExtensions.contains(ext)
        }
        return false
    }
    
    private func isNonFetchAssetPacket(_ packet: SnagPacket) -> Bool {
        if let contentType = packet.requestInfo?.responseContentType?.lowercased() {
            if contentType.contains("image") || contentType.contains("video") || contentType.contains("audio") {
                return true
            }
            if contentType.contains("javascript") || contentType.contains("css") || contentType.contains("font") {
                return true
            }
            return false
        }
        if let ext = urlPathExtension(packet.requestInfo?.url) {
            if Self.mediaPathExtensions.contains(ext) { return true }
            if Self.nonFetchAssetPathExtensions.contains(ext) { return true }
        }
        return false
    }
    
    var categoryFilter: PacketFilterCategory = .all {
        didSet {
            self.refreshItems()
        }
    }
    
    var addressFilterTerm = "" {
        didSet {
            self.refreshItems()
        }
    }
    
    
    private var allPackets: [SnagPacket] {
        if let project = SnagController.shared.selectedProjectController,
           let device = project.selectedDeviceController {
            return device.packets
        } else {
            return SavedRequestsViewModel.shared.savedPackets
        }
    }
    
    
    func register() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didGetPacket, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didUpdatePacket, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectProject, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectDevice, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectPacket, object: nil)
        
        // Observers for Saved Requests
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectSavedPacket, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didUpdateSavedPackets, object: nil)
        
        self.refreshItems()
    }
    
    var selectedItem: SnagPacket? {
        if let project = SnagController.shared.selectedProjectController,
           let device = project.selectedDeviceController {
            return device.selectedPacket
        } else {
            return SnagController.shared.selectedSavedPacket
        }
    }
    
    var selectedItemIndex: Int? {
        guard let selectedItem = self.selectedItem else { return nil }
        
        return self.items.firstIndex { $0 === selectedItem }
    }
    
    @objc func refreshItems() {
        // Skip if update already pending
        if isUpdatePending { return }
        
        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastUpdate)
        
        if timeSinceLast >= updateRateLimit {
            // Update immediately
            performRefresh()
            lastUpdate = Date()
        } else {
            // Schedule for later (at the end of the throttle window)
            isUpdatePending = true
            let delay = updateRateLimit - timeSinceLast
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.isUpdatePending = false
                self.performRefresh()
                self.lastUpdate = Date()
            }
        }
    }
    
    private func performRefresh() {
        items = filter(items: allPackets)
        onChange?()
    }
    
    func filter(items: [SnagPacket]) -> [SnagPacket] {
        let filteredItems = performAddressFiltration(items)
        return performCategoryFiltration(filteredItems)
    }
    
    func performCategoryFiltration(_ items: [SnagPacket]) -> [SnagPacket] {
        switch categoryFilter {
        case .all:
            return items
        case .fetchXHR:
            return items.filter { packet in
                return !isNonFetchAssetPacket(packet)
            }
        case .media:
            return items.filter { packet in
                return isMediaPacket(packet)
            }
        case .status1xx:
            return items.filter { $0.requestInfo?.statusCode?.prefix(1) == "1" }
        case .status2xx:
            return items.filter { $0.requestInfo?.statusCode?.prefix(1) == "2" }
        case .status3xx:
            return items.filter { $0.requestInfo?.statusCode?.prefix(1) == "3" }
        case .status4xx:
            return items.filter { $0.requestInfo?.statusCode?.prefix(1) == "4" }
        case .status5xx:
            return items.filter { $0.requestInfo?.statusCode?.prefix(1) == "5" }
        }
    }
    
    func performAddressFiltration(_ items: [SnagPacket])  -> [SnagPacket] {
        let term = addressFilterTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return items
        }
        
        let lowerTerm = term.lowercased()
        return items.filter {
            guard let url = $0.requestInfo?.url else { return true }
            return url.lowercased().contains(lowerTerm)
        }
    }
    
    
    func clearPackets() {
        if let project = SnagController.shared.selectedProjectController,
           let device = project.selectedDeviceController {
            device.clear()
        } else {
            SavedRequestsViewModel.shared.clearAll()
        }
        self.refreshItems()
    }
    
    var isSavedMode: Bool {
        return SnagController.shared.selectedProjectController == nil
    }
    
    func deletePacket(_ packet: SnagPacket) {
        if isSavedMode {
            SavedRequestsViewModel.shared.delete(packet: packet)
            // No need to manually refresh here as we observer didUpdateSavedPackets
        }
    }
}

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
}

class PacketsViewModel: BaseListViewModel<SnagPacket>  {
    
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
    
    var methodFilterTerm = "" {
        didSet {
            self.refreshItems()
        }
    }
    
    var statusFilterTerm = "" {
        didSet {
            self.refreshItems()
        }
    }
    
    private var allPackets: [SnagPacket] {
        return SnagController.shared.selectedProjectController?.selectedDeviceController?.packets ?? []
    }
    
    
    func register() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didGetPacket, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didUpdatePacket, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectProject, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectDevice, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshItems), name: SnagNotifications.didSelectPacket, object: nil)
        
        self.refreshItems()
    }
    
    var selectedItem: SnagPacket? {
        return SnagController.shared.selectedProjectController?.selectedDeviceController?.selectedPacket
    }
    
    var selectedItemIndex: Int? {
        guard let selectedItem = self.selectedItem else { return nil }
        
        return self.items.firstIndex { $0 === selectedItem }
    }
    
    @objc func refreshItems() {
        items = filter(items: allPackets)
        onChange?()
    }
    
    func filter(items: [SnagPacket]) -> [SnagPacket] {
        var filteredItems = performAddressFiltration(items)
        filteredItems = performMethodFiltration(filteredItems)
        filteredItems = performStatusFiltration(filteredItems)
        return performCategoryFiltration(filteredItems)
    }
    
    func performCategoryFiltration(_ items: [SnagPacket]) -> [SnagPacket] {
        switch categoryFilter {
        case .all:
            return items
        case .fetchXHR:
            // Fetch/XHR typically means main API requests, excluding common static assets
            return items.filter { packet in
                guard let contentType = packet.requestInfo?.responseContentType?.lowercased() else { return true }
                return !contentType.contains("image") && 
                       !contentType.contains("video") && 
                       !contentType.contains("audio") &&
                       !contentType.contains("javascript") &&
                       !contentType.contains("css")
            }
        case .media:
            return items.filter { packet in
                guard let contentType = packet.requestInfo?.responseContentType?.lowercased() else { return false }
                return contentType.contains("image") || 
                       contentType.contains("video") || 
                       contentType.contains("audio")
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
        guard addressFilterTerm.count > 0 else {
            return items
        }
        
        return items.filter {
            $0.requestInfo?.url?.contains(self.addressFilterTerm) ?? true }
    }
    
    func performMethodFiltration(_ items: [SnagPacket])  -> [SnagPacket] {
        guard methodFilterTerm.count > 0 else {
            return items
        }
        
        return items.filter
            { $0.requestInfo?.requestMethod?.rawValue.lowercased()
                .contains(self.methodFilterTerm.lowercased()) ?? true }
    }
    
    func performStatusFiltration(_ items: [SnagPacket])  -> [SnagPacket] {
        guard statusFilterTerm.count > 0 else {
            return items
        }
        
        guard !statusFilterTerm.trimmingCharacters(in: .whitespaces).isEmpty else {
            return items.filter { $0.requestInfo?.statusCode?.trimmingCharacters(in: .whitespaces).isEmpty ?? true}
        }
        
        return items.filter
            { $0.requestInfo?.statusCode?.contains(self.statusFilterTerm) ?? false
        }
    }
    
    func clearPackets() {
        SnagController.shared.selectedProjectController?.selectedDeviceController?.clear()
        self.refreshItems()
    }
}

import Cocoa

class SavedRequestsViewModel: ObservableObject {
    
    static let shared = SavedRequestsViewModel()
    
    @Published var savedPackets: [SnagPacket] = []
    
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    // Directory: Application Support/<BundleID>/SavedRequests/
    private var requestsDirectoryURL: URL? {
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let bundleID = Bundle.main.bundleIdentifier ?? "Snag"
        return appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("SavedRequests")
    }
    
    init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = .prettyPrinted
        self.encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        // Create directory if needed
        if let dir = requestsDirectoryURL {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            }
        }
        
        self.loadRequests()
    }
    
    func loadRequests() {
        guard let dir = requestsDirectoryURL else { return }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            
            var packets: [SnagPacket] = []
            
            for fileURL in jsonFiles {
                if let data = try? Data(contentsOf: fileURL),
                   let packet = try? decoder.decode(SnagPacket.self, from: data) {
                    packets.append(packet)
                }
            }
            
            // Sort by discoveryDate (newest first)
            packets.sort { $0.discoveryDate > $1.discoveryDate }
            
            DispatchQueue.main.async {
                self.savedPackets = packets
                NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)
            }
        } catch {
            print("SavedRequestsViewModel: Error loading requests: \(error)")
        }
    }
    
    func save(packet: SnagPacket) {
        guard let dir = requestsDirectoryURL else { return }
        
        // Ensure packet has an ID
        let id = packet.id
        let fileURL = dir.appendingPathComponent("\(id).json")
        
        if fileManager.fileExists(atPath: fileURL.path) {
            print("SavedRequestsViewModel: Request already saved.")
            return
        }
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try self.encoder.encode(packet)
                try data.write(to: fileURL)
                
                // Reload on main thread
                DispatchQueue.main.async {
                    self.loadRequests()
                }
                
            } catch {
                print("SavedRequestsViewModel: Error saving packet: \(error)")
            }
        }
    }
    
    func delete(packet: SnagPacket) {
        guard let dir = requestsDirectoryURL else { return }
        let fileURL = dir.appendingPathComponent("\(packet.id).json")
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            
            DispatchQueue.main.async {
                if let index = self.savedPackets.firstIndex(where: { $0.id == packet.id }) {
                    self.savedPackets.remove(at: index)
                    NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)
                }
            }
            
        } catch {
            print("SavedRequestsViewModel: Error deleting packet: \(error)")
        }
    }
    
    func clearAll() {
        guard let dir = requestsDirectoryURL else { return }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            
            DispatchQueue.main.async {
                self.savedPackets.removeAll()
                NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)
            }
            
        } catch {
            print("SavedRequestsViewModel: Error clearing all requests: \(error)")
        }
    }
}

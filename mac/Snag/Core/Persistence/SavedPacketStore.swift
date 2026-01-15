import Foundation
import SwiftUI

/// A persistent store for saved network packets, keeping them as structured JSON on disk.
/// This follows the Repository pattern and centralizes disk I/O for saved data.
@MainActor
class SavedPacketStore: ObservableObject {
    static let shared = SavedPacketStore()
    
    @Published var savedPackets: [SnagPacket] = []
    
    private let fileManager = FileManager.default
    private let categoryDirName = "SavedRequests"
    
    private var baseDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupport.appendingPathComponent("Snag", isDirectory: true)
        let dir = base.appendingPathComponent(categoryDirName, isDirectory: true)
        
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }
    
    private init() {
        migrateIfNeeded()
        loadAll()
    }
    
    private func migrateIfNeeded() {
        // Migration from legacy Documents folder to Application Support
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldDir = docs.appendingPathComponent("Snag").appendingPathComponent(categoryDirName)
        
        guard fileManager.fileExists(atPath: oldDir.path) else { return }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil)
            for file in files {
                let dest = baseDirectory.appendingPathComponent(file.lastPathComponent)
                if !fileManager.fileExists(atPath: dest.path) {
                    try fileManager.moveItem(at: file, to: dest)
                }
            }
            try? fileManager.removeItem(at: oldDir)
        } catch {
            print("Migration failed: \(error)")
        }
    }
    
    func loadAll() {
        do {
            let files = try fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            let sortedFiles = files.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return d1 > d2
            }
            
            var packets: [SnagPacket] = []
            let decoder = JSONDecoder()
            
            for file in sortedFiles {
                if file.pathExtension == "json",
                   let data = try? Data(contentsOf: file),
                   let packet = try? decoder.decode(SnagPacket.self, from: data) {
                    packets.append(packet)
                }
            }
            self.savedPackets = packets
        } catch {
            print("Failed to load saved requests: \(error)")
        }
    }
    
    func save(packet: SnagPacket) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(packet)
            let filename = (packet.packetId ?? UUID().uuidString) + ".json"
            let fileURL = baseDirectory.appendingPathComponent(filename)
            try data.write(to: fileURL)
            
            loadAll()
            NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)
        } catch {
            print("Failed to save packet: \(error)")
        }
    }
    
    func delete(packet: SnagPacket) {
        let filename = (packet.packetId ?? UUID().uuidString) + ".json"
        let fileURL = baseDirectory.appendingPathComponent(filename)
        
        try? fileManager.removeItem(at: fileURL)
        loadAll()
        NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)
    }
    
    func clearAll() {
        try? fileManager.removeItem(at: baseDirectory)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        loadAll()
        NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)
    }
}

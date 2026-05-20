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
        let dir = baseDirectory
        Task.detached(priority: .utility) { [weak self] in
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: .skipsHiddenFiles
                )

                let dated: [(URL, Date)] = files.compactMap { file in
                    guard file.pathExtension == "json" else { return nil }
                    let date = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return (file, date)
                }

                let sortedFiles = dated.sorted { $0.1 > $1.1 }.map { $0.0 }

                var packets: [SnagPacket] = []
                packets.reserveCapacity(sortedFiles.count)
                let decoder = JSONDecoder()

                for file in sortedFiles {
                    if let data = try? Data(contentsOf: file),
                       let packet = try? decoder.decode(SnagPacket.self, from: data) {
                        packets.append(packet)
                    }
                }
                await MainActor.run {
                    self?.savedPackets = packets
                    NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)
                }
            } catch {
                print("Failed to load saved requests: \(error)")
            }
        }
    }

    func save(packet: SnagPacket) {
        // Update in-memory state immediately so UI reflects the change without waiting for disk I/O.
        if let existingIndex = savedPackets.firstIndex(where: { $0.packetId == packet.packetId }) {
            savedPackets[existingIndex] = packet
        } else {
            savedPackets.insert(packet, at: 0)
        }
        NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)

        let fileURL = baseDirectory.appendingPathComponent((packet.packetId ?? UUID().uuidString) + ".json")
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            do {
                let data = try encoder.encode(packet)
                try data.write(to: fileURL)
            } catch {
                print("Failed to save packet: \(error)")
            }
        }
    }

    func delete(packet: SnagPacket) {
        savedPackets.removeAll { $0.packetId == packet.packetId }
        NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)

        let fileURL = baseDirectory.appendingPathComponent((packet.packetId ?? UUID().uuidString) + ".json")
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func clearAll() {
        savedPackets.removeAll()
        NotificationCenter.default.post(name: SnagNotifications.didUpdateSavedPackets, object: nil)

        let dir = baseDirectory
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }
}

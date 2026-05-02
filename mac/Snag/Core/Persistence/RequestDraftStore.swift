import Foundation

/// Persistent store for request drafts. One JSON file per draft under
/// `Application Support/Snag/Drafts/`. Mirrors `SavedPacketStore`.
@MainActor
final class RequestDraftStore: ObservableObject {
    static let shared = RequestDraftStore()

    @Published private(set) var drafts: [RequestDraft] = []

    private let fileManager = FileManager.default
    private let categoryDirName = "Drafts"
    private var saveTask: [String: Task<Void, Never>] = [:]
    private let saveDebounceSeconds: TimeInterval = 0.5

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
        loadAll()
    }

    func loadAll() {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )

            let dated: [(URL, Date)] = files.compactMap { file in
                guard file.pathExtension == "json" else { return nil }
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return (file, date)
            }

            let sortedFiles = dated.sorted { $0.1 > $1.1 }.map { $0.0 }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var loaded: [RequestDraft] = []
            loaded.reserveCapacity(sortedFiles.count)
            for file in sortedFiles {
                if let bytes = try? Data(contentsOf: file),
                   let data = try? decoder.decode(RequestDraftData.self, from: bytes) {
                    loaded.append(RequestDraft(data: data))
                }
            }
            self.drafts = loaded
        } catch {
            print("Failed to load drafts: \(error)")
        }
    }

    func upsert(_ draft: RequestDraft) {
        // Refresh updatedAt and persist immediately (used at Send / tab close).
        draft.data.updatedAt = Date()
        writeToDisk(draft.data)
        applyToList(draft)
        draft.isDirty = false
        NotificationCenter.default.post(name: SnagNotifications.didUpdateDrafts, object: nil)
    }

    /// Debounced write — call from editors to avoid disk thrash on each keystroke.
    func scheduleSave(_ draft: RequestDraft) {
        draft.isDirty = true
        let id = draft.id
        saveTask[id]?.cancel()
        saveTask[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.saveDebounceSeconds ?? 0.5) * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run {
                self?.upsert(draft)
            }
        }
    }

    func delete(_ draft: RequestDraft) {
        let url = baseDirectory.appendingPathComponent(draft.id + ".json")
        try? fileManager.removeItem(at: url)
        drafts.removeAll { $0.id == draft.id }
        saveTask[draft.id]?.cancel()
        saveTask[draft.id] = nil
        NotificationCenter.default.post(name: SnagNotifications.didUpdateDrafts, object: nil)
    }

    @discardableResult
    func duplicate(_ draft: RequestDraft) -> RequestDraft {
        var copy = draft.data
        copy.id = UUID().uuidString
        copy.name = copy.name.isEmpty ? "" : copy.name + " " + "(copy)".localized
        copy.createdAt = Date()
        copy.updatedAt = Date()
        let new = RequestDraft(data: copy)
        upsert(new)
        return new
    }

    func draft(withId id: String) -> RequestDraft? {
        drafts.first { $0.id == id }
    }

    // MARK: - Private

    private func writeToDisk(_ data: RequestDraftData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        do {
            let bytes = try encoder.encode(data)
            let url = baseDirectory.appendingPathComponent(data.id + ".json")
            try bytes.write(to: url, options: .atomic)
        } catch {
            print("Failed to save draft \(data.id): \(error)")
        }
    }

    private func applyToList(_ draft: RequestDraft) {
        if let idx = drafts.firstIndex(where: { $0.id == draft.id }) {
            // Move to top to mimic "most recently updated".
            if idx != 0 {
                drafts.remove(at: idx)
                drafts.insert(draft, at: 0)
            }
        } else {
            drafts.insert(draft, at: 0)
        }
    }
}

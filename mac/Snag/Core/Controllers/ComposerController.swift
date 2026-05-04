import Foundation
import Combine

@MainActor
final class ComposerController: ObservableObject {
    static let shared = ComposerController()

    @Published var openDraftIds: [String] = []
    @Published var activeDraftId: String?

    private let openDraftIdsKey = SnagConstants.composerOpenDraftIdsKey
    private let activeDraftIdKey = SnagConstants.composerActiveDraftIdKey

    private init() {
        restorePersisted()
    }

    func newBlankDraft() -> RequestDraft {
        let data = RequestDraftData()
        let draft = RequestDraft(data: data)
        RequestDraftStore.shared.upsert(draft)
        open(draft)
        return draft
    }

    @discardableResult
    func newDraft(from packet: SnagPacket) -> RequestDraft {
        let data = RequestDraftData.from(packet)
        let draft = RequestDraft(data: data)
        RequestDraftStore.shared.upsert(draft)
        open(draft)
        return draft
    }

    /// Project parsed import data onto a draft. When `replaceActive` is true and an active
    /// draft exists, the active draft's URL/method/headers/body etc. are replaced — its
    /// `id`, `name`, and `createdAt` are kept so tabs and bookmarks survive.
    @discardableResult
    func importDraft(_ data: RequestDraftData, replaceActive: Bool = false) -> RequestDraft {
        if replaceActive, let active = activeDraft {
            var merged = data
            merged.id = active.data.id
            merged.name = active.data.name
            merged.createdAt = active.data.createdAt
            merged.updatedAt = Date()
            active.data = merged
            RequestDraftStore.shared.upsert(active)
            return active
        }
        let draft = RequestDraft(data: data)
        RequestDraftStore.shared.upsert(draft)
        open(draft)
        return draft
    }

    /// Bulk-apply a parsed `ImportableBatch` onto the draft store, opening the
    /// requested subset as tabs. Returns a summary the caller can show as a
    /// toast / sheet line.
    @discardableResult
    func importBatch(_ batch: ImportableBatch,
                     selected: Set<UUID>,
                     options: BatchImportOptions) -> ImportResult {
        let chosen = batch.requests.filter { selected.contains($0.id) }
        if chosen.isEmpty {
            return ImportResult(imported: 0, skipped: 0, opened: 0, failed: 0)
        }

        // Pre-existing canonical hashes — used to detect duplicates without
        // re-hashing every existing draft per row.
        let existingHashes: Set<String> = options.skipDuplicates
            ? Set(RequestDraftStore.shared.drafts.map { ImportableRequest.canonicalHash(of: $0.data) })
            : []

        var draftsToUpsert: [RequestDraft] = []
        var skipped = 0

        for req in chosen {
            if options.skipDuplicates, existingHashes.contains(req.sourceHash) {
                skipped += 1
                continue
            }

            var data = req.draftData
            data.id = UUID().uuidString
            if options.prefixWithFolderPath, !req.folderPath.isEmpty {
                let prefix = req.folderPath.joined(separator: " › ")
                data.name = "\(prefix) › \(req.name)"
            } else {
                data.name = req.name
            }
            data.createdAt = Date()
            data.updatedAt = Date()
            draftsToUpsert.append(RequestDraft(data: data))
        }

        RequestDraftStore.shared.upsertMany(draftsToUpsert)

        var openedCount = 0
        switch options.openMode {
        case .openAllAsTabs:
            for d in draftsToUpsert { open(d); openedCount += 1 }
        case .saveAndOpenFirst(let n):
            for d in draftsToUpsert.prefix(n) { open(d); openedCount += 1 }
        case .saveOnly:
            break
        }

        return ImportResult(
            imported: draftsToUpsert.count,
            skipped: skipped,
            opened: openedCount,
            failed: 0
        )
    }

    func open(_ draft: RequestDraft) {
        if !openDraftIds.contains(draft.id) {
            openDraftIds.append(draft.id)
        }
        activeDraftId = draft.id
        persist()
        NotificationCenter.default.post(name: SnagNotifications.didOpenDraft, object: draft.id)
    }

    func close(_ draftId: String) {
        openDraftIds.removeAll { $0 == draftId }
        if activeDraftId == draftId {
            activeDraftId = openDraftIds.last
        }
        persist()
        NotificationCenter.default.post(name: SnagNotifications.didCloseDraft, object: draftId)
    }

    func activate(_ draftId: String) {
        guard openDraftIds.contains(draftId) else { return }
        activeDraftId = draftId
        persist()
    }

    func handleDraftDeletion(_ draftId: String) {
        close(draftId)
    }

    /// Drop ids whose drafts no longer exist in the store. Call after store load.
    func reconcileWithStore() {
        let knownIds = Set(RequestDraftStore.shared.drafts.map { $0.id })
        openDraftIds = openDraftIds.filter { knownIds.contains($0) }
        if let active = activeDraftId, !knownIds.contains(active) {
            activeDraftId = openDraftIds.last
        }
        persist()
    }

    var activeDraft: RequestDraft? {
        guard let id = activeDraftId else { return nil }
        return RequestDraftStore.shared.draft(withId: id)
    }

    // MARK: - Persistence

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(openDraftIds, forKey: openDraftIdsKey)
        defaults.set(activeDraftId, forKey: activeDraftIdKey)
    }

    private func restorePersisted() {
        let defaults = UserDefaults.standard
        if let ids = defaults.array(forKey: openDraftIdsKey) as? [String] {
            openDraftIds = ids
        }
        activeDraftId = defaults.string(forKey: activeDraftIdKey)
    }
}

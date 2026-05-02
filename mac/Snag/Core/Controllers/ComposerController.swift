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

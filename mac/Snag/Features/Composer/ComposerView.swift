import SwiftUI

struct ComposerView: View {
    @ObservedObject var composer: ComposerController = ComposerController.shared
    @ObservedObject var store: RequestDraftStore = RequestDraftStore.shared

    var body: some View {
        VStack(spacing: 0) {
            ComposerTabStrip()
            Divider()

            if let draft = composer.activeDraft {
                DraftEditorView(draft: draft)
                    .id(draft.id)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.dashed.and.paperclip")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)
            Text("No draft selected".localized)
                .font(.system(size: 13, weight: .medium))
            Text("Right-click a captured request and choose 'Edit & Resend', or click + above.".localized)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("New Draft".localized) {
                _ = composer.newBlankDraft()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

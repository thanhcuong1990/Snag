import SwiftUI

struct ComposerTabStrip: View {
    @ObservedObject var composer: ComposerController = ComposerController.shared
    @ObservedObject var store: RequestDraftStore = RequestDraftStore.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(composer.openDraftIds, id: \.self) { id in
                    if let draft = store.draft(withId: id) {
                        ComposerTab(draft: draft, isActive: composer.activeDraftId == id)
                            .onTapGesture { composer.activate(id) }
                    }
                }

                Button(action: { _ = composer.newBlankDraft() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(PlainButtonStyle())
                .help("New Draft".localized)

                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .frame(height: 32)
        .background(Color(nsColor: ThemeColor.contentBarColor))
    }
}

struct ComposerTab: View {
    @ObservedObject var draft: RequestDraft
    let isActive: Bool
    @ObservedObject var composer: ComposerController = ComposerController.shared

    var body: some View {
        HStack(spacing: 6) {
            Text(draft.data.method.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Text(draft.data.displayName + (draft.isDirty ? " *" : ""))
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(isActive ? .primary : .secondary)
            Button(action: { composer.close(draft.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color(nsColor: .selectedControlColor).opacity(0.4) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.25), lineWidth: isActive ? 0 : 0.5)
        )
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}

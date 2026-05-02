import SwiftUI

struct DraftSidebarSection: View {
    @ObservedObject var store: RequestDraftStore = RequestDraftStore.shared
    @ObservedObject var composer: ComposerController = ComposerController.shared
    @ObservedObject var snagController: SnagController = SnagController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("COMPOSER".localized)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondaryLabelColor)
                Spacer()
                Button(action: { _ = composer.newBlankDraft(); snagController.selectCompose() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondaryLabelColor)
                }
                .buttonStyle(PlainButtonStyle())
                .help("New Draft".localized)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if store.drafts.isEmpty {
                Text("No drafts yet".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryLabelColor)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.drafts) { draft in
                        DraftSidebarRow(draft: draft)
                    }
                }
            }
        }
    }
}

struct DraftSidebarRow: View {
    @ObservedObject var draft: RequestDraft
    @ObservedObject var composer: ComposerController = ComposerController.shared
    @ObservedObject var snagController: SnagController = SnagController.shared

    private var isSelected: Bool {
        snagController.route == .compose && composer.activeDraftId == draft.id
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(draft.data.method.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(methodColor(for: draft.data.method))
                .frame(width: 36, alignment: .leading)

            Text(draft.data.displayName + (draft.isDirty ? " *" : ""))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .labelColor)

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
        .onTapGesture {
            composer.open(draft)
            snagController.selectCompose()
        }
        .contextMenu {
            Button("Rename".localized) {
                renameDraft()
            }
            Button("Duplicate".localized) {
                _ = RequestDraftStore.shared.duplicate(draft)
            }
            Divider()
            Button("Delete".localized, role: .destructive) {
                composer.handleDraftDeletion(draft.id)
                RequestDraftStore.shared.delete(draft)
            }
        }
    }

    private func renameDraft() {
        let alert = NSAlert()
        alert.messageText = "Rename Draft".localized
        alert.informativeText = "Choose a name for this draft.".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        textField.stringValue = draft.data.name
        textField.placeholderString = draft.data.displayName
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        draft.data.name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        RequestDraftStore.shared.scheduleSave(draft)
    }

    private func methodColor(for method: String) -> Color {
        switch method.uppercased() {
        case "GET":    return .methodGet
        case "POST":   return .methodPost
        case "PUT":    return .methodPut
        case "PATCH":  return .methodPatch
        case "DELETE": return .methodDelete
        default:       return .secondaryLabelColor
        }
    }
}

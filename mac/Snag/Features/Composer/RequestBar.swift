import SwiftUI

struct RequestBar: View {
    @ObservedObject var draft: RequestDraft
    @ObservedObject var sender: RequestSender = RequestSender.shared
    let onSend: () -> Void

    private static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: methodBinding) {
                ForEach(Self.methods, id: \.self) { m in
                    Text(m).tag(m)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 110)

            TextField("https://api.example.com/path".localized, text: urlBinding)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12).monospaced())

            if sender.isSending(draftId: draft.id) {
                Button(action: { sender.cancel(draft.id) }) {
                    Text("Cancel".localized)
                        .frame(minWidth: 64)
                }
                .keyboardShortcut(".", modifiers: [.command])
            } else {
                Button(action: onSend) {
                    Text("Send".localized)
                        .frame(minWidth: 64)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(draft.data.url.isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var methodBinding: Binding<String> {
        Binding(
            get: { draft.data.method },
            set: { draft.data.method = $0; RequestDraftStore.shared.scheduleSave(draft) }
        )
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: { draft.data.url },
            set: {
                draft.data.url = $0
                draft.data.queryParams = RequestDraftData.parseQueryItems(from: $0)
                RequestDraftStore.shared.scheduleSave(draft)
            }
        )
    }
}

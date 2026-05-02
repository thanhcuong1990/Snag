import SwiftUI

struct BodyEditorView: View {
    @ObservedObject var draft: RequestDraft

    private static let encodingOptions: [BodyEncoding] = [.text, .json, .base64, .multipart]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: encodingBinding) {
                    ForEach(Self.encodingOptions, id: \.self) { e in
                        Text(label(for: e)).tag(e)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)
                .labelsHidden()

                if draft.data.bodyEncoding != .multipart {
                    TextField("Content-Type".localized, text: contentTypeBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(maxWidth: 260)
                } else {
                    Text("multipart/form-data")
                        .font(.system(size: 11).monospaced())
                        .foregroundColor(.secondary)
                }

                Spacer()

                if draft.data.bodyEncoding == .json {
                    Button(action: formatJSON) {
                        Text("Format".localized)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canFormatJSON)
                }

                if draft.data.bodyEncoding != .multipart {
                    Text(sizeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: ThemeColor.contentBarColor))

            Divider()

            switch draft.data.bodyEncoding {
            case .base64:
                base64ReadOnly
            case .multipart:
                MultipartEditorView(draft: draft)
            case .text, .json:
                EditableCodeTextView(text: bodyTextBinding,
                                     highlightJSON: draft.data.bodyEncoding == .json)
            }
        }
    }

    private var canFormatJSON: Bool {
        guard let str = currentBodyString(), !str.isEmpty else { return false }
        let sanitized = Self.sanitizeSmartQuotes(str)
        return (try? JSONSerialization.jsonObject(with: Data(sanitized.utf8),
                                                   options: [.fragmentsAllowed])) != nil
    }

    private func formatJSON() {
        guard let str = currentBodyString() else { return }
        let sanitized = Self.sanitizeSmartQuotes(str)
        guard let obj = try? JSONSerialization.jsonObject(with: Data(sanitized.utf8),
                                                          options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                       options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let out = String(data: pretty, encoding: .utf8) else { return }
        draft.data.bodyBase64 = Data(out.utf8).base64EncodedString()
        RequestDraftStore.shared.scheduleSave(draft)
    }

    private func currentBodyString() -> String? {
        guard let b64 = draft.data.bodyBase64,
              let data = Data(base64Encoded: b64),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private static let smartQuoteMap: [Character: Character] = [
        "\u{201C}": "\"", "\u{201D}": "\"",
        "\u{2018}": "'",  "\u{2019}": "'",
    ]

    /// AppKit's smart-quote substitution sometimes slips past `isAutomaticQuoteSubstitutionEnabled`,
    /// leaving curly quotes that JSON parsers reject. Normalize them so Format can recover.
    private static func sanitizeSmartQuotes(_ s: String) -> String {
        String(s.map { smartQuoteMap[$0] ?? $0 })
    }

    private var base64ReadOnly: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Binary body (Base64). Switch to Text or JSON to edit as plain text.".localized)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            ScrollView {
                Text(draft.data.bodyBase64 ?? "")
                    .font(.system(size: 11).monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
    }

    // MARK: - Bindings

    private var encodingBinding: Binding<BodyEncoding> {
        Binding(
            get: { draft.data.bodyEncoding },
            set: {
                draft.data.bodyEncoding = $0
                RequestDraftStore.shared.scheduleSave(draft)
            }
        )
    }

    private var contentTypeBinding: Binding<String> {
        Binding(
            get: { draft.data.bodyContentType ?? "" },
            set: {
                draft.data.bodyContentType = $0.isEmpty ? nil : $0
                RequestDraftStore.shared.scheduleSave(draft)
            }
        )
    }

    private var bodyTextBinding: Binding<String> {
        Binding(
            get: {
                guard let b64 = draft.data.bodyBase64,
                      let data = Data(base64Encoded: b64),
                      let s = String(data: data, encoding: .utf8) else { return "" }
                return s
            },
            set: { newText in
                if newText.isEmpty {
                    draft.data.bodyBase64 = nil
                } else {
                    draft.data.bodyBase64 = Data(newText.utf8).base64EncodedString()
                }
                RequestDraftStore.shared.scheduleSave(draft)
            }
        )
    }

    private var sizeLabel: String {
        let bytes = (draft.data.bodyBase64.flatMap { Data(base64Encoded: $0) })?.count ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func label(for encoding: BodyEncoding) -> String {
        switch encoding {
        case .text: return "Text".localized
        case .json: return "JSON".localized
        case .base64: return "Binary".localized
        case .multipart: return "Multipart".localized
        }
    }
}

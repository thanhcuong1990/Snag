import SwiftUI

struct DraftCurlPreviewView: View {
    @ObservedObject var draft: RequestDraft

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: copyToPasteboard) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy".localized)
                    }
                    .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: ThemeColor.contentBarColor))

            Divider()

            CodeTextView(text: curlCommand)
                .padding(.vertical, 4)
        }
    }

    private var curlCommand: String {
        var parts: [String] = ["curl", "-X \(draft.data.method.uppercased())"]

        let isMultipart = draft.data.bodyEncoding == .multipart
        for h in draft.data.headers where h.enabled && !h.key.isEmpty {
            // Multipart: curl computes its own Content-Type/boundary, so skip user's.
            if isMultipart, h.key.caseInsensitiveCompare("Content-Type") == .orderedSame { continue }
            let k = h.key.replacingOccurrences(of: "\"", with: "\\\"")
            let v = h.value.replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("-H \"\(k): \(v)\"")
        }

        if isMultipart {
            for p in draft.data.multipartParts where p.enabled && !p.name.isEmpty {
                let name = Self.shellEscape(p.name)
                switch p.kind {
                case .text:
                    parts.append("-F '\(name)=\(Self.shellEscape(p.textValue))'")
                case .file:
                    if let s = p.fileURL, let url = URL(string: s), url.isFileURL {
                        var spec = "@\(Self.shellEscape(url.path))"
                        if let ct = p.contentType?.nilIfEmpty {
                            spec += ";type=\(ct)"
                        }
                        if let fn = p.fileName?.nilIfEmpty, fn != url.lastPathComponent {
                            spec += ";filename=\(fn)"
                        }
                        parts.append("-F '\(name)=\(spec)'")
                    } else {
                        parts.append("-F '\(name)=@<no file>'")
                    }
                }
            }
        } else if let b64 = draft.data.bodyBase64, !b64.isEmpty {
            let bodyText: String
            if let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                bodyText = s
            } else {
                bodyText = "[binary]"
            }
            parts.append("--data-raw '\(Self.shellEscape(bodyText))'")
        }

        let url = draft.data.rebuildURL()
        parts.append("\"\(url)\"")
        return parts.joined(separator: " \\\n\t")
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(curlCommand, forType: .string)
    }

    /// Bourne-shell single-quote escape: end the quoted run, emit `'\''`, restart it.
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }
}

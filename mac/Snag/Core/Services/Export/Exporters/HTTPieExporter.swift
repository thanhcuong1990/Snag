import Foundation

/// Generates an `http` (HTTPie) command for a draft.
/// Header: `Name:Value`. Form field: `field=value`. JSON field: `field:=…`.
/// Multipart: `-f field@/path/to/file`. Body: `--raw '<bytes>'`.
enum HTTPieExporter: RequestExporter {

    static func export(_ draft: RequestDraftData) -> String {
        var parts: [String] = ["http"]

        // HTTPie auto-infers JSON; we hint with `--json` when bodyEncoding == .json.
        if draft.bodyEncoding == .json { parts.append("--json") }
        if draft.bodyEncoding == .multipart { parts.append("--multipart") }

        parts.append(draft.method.uppercased())
        parts.append("'\(shellEscape(draft.rebuildURL()))'")

        for h in draft.headers where h.enabled && !h.key.isEmpty {
            // Skip user-supplied multipart Content-Type — HTTPie sets the boundary.
            if draft.bodyEncoding == .multipart,
               h.key.caseInsensitiveCompare("Content-Type") == .orderedSame {
                continue
            }
            parts.append("'\(shellEscape("\(h.key):\(h.value)"))'")
        }

        if draft.bodyEncoding == .multipart {
            for p in draft.multipartParts where p.enabled && !p.name.isEmpty {
                switch p.kind {
                case .text:
                    parts.append("'\(shellEscape("\(p.name)=\(p.textValue)"))'")
                case .file:
                    if let s = p.fileURL, let url = URL(string: s), url.isFileURL {
                        parts.append("'\(shellEscape("\(p.name)@\(url.path)"))'")
                    } else {
                        parts.append("# \(p.name)@<no file>")
                    }
                }
            }
        } else if let b64 = draft.bodyBase64, !b64.isEmpty {
            if let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                parts.append("--raw")
                parts.append("'\(shellEscape(s))'")
            } else {
                parts.append("# binary body — encode separately and pipe via stdin")
            }
        }

        return parts.joined(separator: " \\\n\t")
    }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }
}

import Foundation

/// Generates a `curl` command for a draft. Pure function — no UI.
/// Round-trip: `CurlImporter.parse(CurlExporter.export(d))` produces a
/// draft semantically equivalent to `d` for the supported field subset.
enum CurlExporter: RequestExporter {

    static func export(_ draft: RequestDraftData) -> String {
        var parts: [String] = ["curl", "-X \(draft.method.uppercased())"]

        let isMultipart = draft.bodyEncoding == .multipart
        for h in draft.headers where h.enabled && !h.key.isEmpty {
            // Multipart: cURL computes its own Content-Type/boundary, so skip user's.
            if isMultipart, h.key.caseInsensitiveCompare("Content-Type") == .orderedSame {
                continue
            }
            let k = h.key.replacingOccurrences(of: "\"", with: "\\\"")
            let v = h.value.replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("-H \"\(k): \(v)\"")
        }

        if isMultipart {
            for p in draft.multipartParts where p.enabled && !p.name.isEmpty {
                let name = shellEscape(p.name)
                switch p.kind {
                case .text:
                    parts.append("-F '\(name)=\(shellEscape(p.textValue))'")
                case .file:
                    if let s = p.fileURL, let url = URL(string: s), url.isFileURL {
                        var spec = "@\(shellEscape(url.path))"
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
        } else if let b64 = draft.bodyBase64, !b64.isEmpty {
            let bodyText: String
            if let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                bodyText = s
            } else {
                bodyText = "[binary]"
            }
            parts.append("--data-raw '\(shellEscape(bodyText))'")
        }

        let url = draft.rebuildURL()
        parts.append("\"\(url)\"")
        return parts.joined(separator: " \\\n\t")
    }

    /// Bourne-shell single-quote escape: end the quoted run, emit `'\''`, restart it.
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }
}

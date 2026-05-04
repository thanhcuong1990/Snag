import Foundation

/// Generates a raw HTTP/1.1 wire-format request — useful for `nc`, hex
/// editors, or pasting into a debugger. CR/LF line endings; ends with a
/// blank line before the body.
enum RawHTTPExporter: RequestExporter {

    static func export(_ draft: RequestDraftData) -> String {
        let url = URL(string: draft.rebuildURL())
        let host = url?.host ?? ""
        let path: String = {
            guard let url else { return draft.rebuildURL() }
            var p = url.path.isEmpty ? "/" : url.path
            if let q = url.query, !q.isEmpty { p += "?\(q)" }
            return p
        }()
        let port = url?.port

        var lines: [String] = []
        lines.append("\(draft.method.uppercased()) \(path) HTTP/1.1")

        // Host header is mandatory — synthesize from URL if not set.
        let hasHostHeader = draft.headers.contains {
            $0.enabled && $0.key.caseInsensitiveCompare("Host") == .orderedSame
        }
        if !hasHostHeader, !host.isEmpty {
            let hostLine = port.map { "\(host):\($0)" } ?? host
            lines.append("Host: \(hostLine)")
        }

        for h in draft.headers where h.enabled && !h.key.isEmpty {
            // Reject CR/LF in keys/values (header injection guardrail).
            let safeKey = h.key.replacingOccurrences(of: "\r", with: "")
                              .replacingOccurrences(of: "\n", with: "")
            let safeValue = h.value.replacingOccurrences(of: "\r", with: "")
                                  .replacingOccurrences(of: "\n", with: "")
            lines.append("\(safeKey): \(safeValue)")
        }

        var body = ""
        if draft.bodyEncoding == .multipart {
            body = "[multipart/form-data — boundary built at send time]"
        } else if let b64 = draft.bodyBase64, !b64.isEmpty {
            if let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                body = s
            } else {
                body = "[binary — \(b64.count) bytes (base64)]"
            }
        }

        lines.append("") // blank line separating headers from body
        lines.append(body)

        return lines.joined(separator: "\r\n")
    }
}

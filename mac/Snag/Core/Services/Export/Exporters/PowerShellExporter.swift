import Foundation

/// `Invoke-WebRequest` snippet. Headers go in a hashtable, body via `-Body`.
enum PowerShellExporter: RequestExporter {

    static func export(_ draft: RequestDraftData) -> String {
        var lines: [String] = []

        // Build a $headers hashtable.
        let entries = draft.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .filter { !($0.key.caseInsensitiveCompare("Content-Type") == .orderedSame &&
                        draft.bodyEncoding == .multipart) }
        if !entries.isEmpty {
            lines.append("$headers = @{")
            for h in entries {
                lines.append("    \(psString(h.key)) = \(psString(h.value))")
            }
            lines.append("}")
            lines.append("")
        }

        var args: [String] = [
            "-Uri \(psString(draft.rebuildURL()))",
            "-Method \(draft.method.uppercased())"
        ]
        if !entries.isEmpty { args.append("-Headers $headers") }

        switch draft.bodyEncoding {
        case .multipart:
            // Build a multipart Form= hashtable.
            lines.append("$form = @{")
            for p in draft.multipartParts where p.enabled && !p.name.isEmpty {
                switch p.kind {
                case .text:
                    lines.append("    \(psString(p.name)) = \(psString(p.textValue))")
                case .file:
                    if let s = p.fileURL, let u = URL(string: s) {
                        lines.append("    \(psString(p.name)) = Get-Item \(psString(u.path))")
                    } else {
                        lines.append("    \(psString(p.name)) = Get-Item \"<no file>\"")
                    }
                }
            }
            lines.append("}")
            lines.append("")
            args.append("-Form $form")

        case .json, .text, .base64:
            if let b64 = draft.bodyBase64, !b64.isEmpty {
                if let data = Data(base64Encoded: b64),
                   let s = String(data: data, encoding: .utf8) {
                    args.append("-Body \(psString(s))")
                } else {
                    lines.append("$bodyBytes = [System.Convert]::FromBase64String(\(psString(b64)))")
                    lines.append("")
                    args.append("-Body $bodyBytes")
                }
            }
        }

        lines.append("$response = Invoke-WebRequest \\")
        for (i, a) in args.enumerated() {
            lines.append(i == args.count - 1 ? "    \(a)" : "    \(a) \\")
        }
        lines.append("$response.StatusCode")
        lines.append("$response.Content")
        return lines.joined(separator: "\n")
    }

    /// PowerShell single-quoted string. Single quotes are escaped by doubling.
    private static func psString(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "''"))'"
    }
}

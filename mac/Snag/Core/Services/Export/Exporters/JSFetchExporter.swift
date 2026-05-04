import Foundation

/// Browser/Node `fetch(url, options)` snippet. Multipart: builds `FormData`
/// with comments noting that `<input type=file>` values must be supplied
/// at runtime.
enum JSFetchExporter: RequestExporter {

    static func export(_ draft: RequestDraftData) -> String {
        var lines: [String] = []

        let url = jsString(draft.rebuildURL())
        let method = jsString(draft.method.uppercased())

        let headerPairs: [String] = draft.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .filter { !($0.key.caseInsensitiveCompare("Content-Type") == .orderedSame &&
                        draft.bodyEncoding == .multipart) }
            .map { "    \(jsString($0.key)): \(jsString($0.value))" }

        let headersBlock: String =
            headerPairs.isEmpty
                ? "{}"
                : "{\n\(headerPairs.joined(separator: ",\n"))\n  }"

        switch draft.bodyEncoding {
        case .multipart:
            lines.append("const form = new FormData();")
            for p in draft.multipartParts where p.enabled && !p.name.isEmpty {
                switch p.kind {
                case .text:
                    lines.append("form.append(\(jsString(p.name)), \(jsString(p.textValue)));")
                case .file:
                    lines.append("// Replace with a File/Blob obtained from <input type=\"file\">.")
                    lines.append("form.append(\(jsString(p.name)), /* file */ null);")
                }
            }
            lines.append("")
            lines.append("const response = await fetch(\(url), {")
            lines.append("  method: \(method),")
            lines.append("  headers: \(headersBlock),")
            lines.append("  body: form,")
            lines.append("});")

        case .json:
            let bodyValue: String
            if let b64 = draft.bodyBase64, !b64.isEmpty,
               let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                bodyValue = "JSON.stringify(\(s.isEmpty ? "null" : s))"
            } else {
                bodyValue = "undefined"
            }
            lines.append("const response = await fetch(\(url), {")
            lines.append("  method: \(method),")
            lines.append("  headers: \(headersBlock),")
            lines.append("  body: \(bodyValue),")
            lines.append("});")

        default:
            let bodyValue: String
            if let b64 = draft.bodyBase64, !b64.isEmpty,
               let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                bodyValue = jsString(s)
            } else if (draft.bodyBase64?.isEmpty == false) {
                bodyValue = "/* binary body — Uint8Array(...) */ undefined"
            } else {
                bodyValue = "undefined"
            }
            lines.append("const response = await fetch(\(url), {")
            lines.append("  method: \(method),")
            lines.append("  headers: \(headersBlock),")
            lines.append("  body: \(bodyValue),")
            lines.append("});")
        }

        lines.append("const text = await response.text();")
        lines.append("console.log(response.status, text);")
        return lines.joined(separator: "\n")
    }

    /// JS double-quoted string with safe escapes (also escapes `</` to avoid
    /// breaking out of inline `<script>` tags).
    static func jsString(_ s: String) -> String {
        var out = "\""
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(c)
            }
        }
        out += "\""
        return out.replacingOccurrences(of: "</", with: "<\\/")
    }
}

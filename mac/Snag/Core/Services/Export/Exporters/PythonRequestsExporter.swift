import Foundation

/// Python `requests` snippet. Detects JSON content-type and emits `json=`,
/// urlencoded → `data=` (dict), multipart → `files=` + `data=`.
enum PythonRequestsExporter: RequestExporter {

    static func export(_ draft: RequestDraftData) -> String {
        var lines: [String] = ["import requests", ""]

        let url = pyString(draft.rebuildURL())
        let method = pyString(draft.method.uppercased())

        let headerPairs: [String] = draft.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .filter { !($0.key.caseInsensitiveCompare("Content-Type") == .orderedSame &&
                        draft.bodyEncoding == .multipart) }
            .map { "    \(pyString($0.key)): \(pyString($0.value))" }

        let headersBlock: String =
            headerPairs.isEmpty
                ? "{}"
                : "{\n\(headerPairs.joined(separator: ",\n"))\n}"

        switch draft.bodyEncoding {
        case .multipart:
            let textParts = draft.multipartParts.filter { $0.enabled && $0.kind == .text && !$0.name.isEmpty }
            let fileParts = draft.multipartParts.filter { $0.enabled && $0.kind == .file && !$0.name.isEmpty }

            let dataDict: String =
                textParts.isEmpty ? "{}" :
                "{\n" + textParts.map { "    \(pyString($0.name)): \(pyString($0.textValue))" }
                              .joined(separator: ",\n") + "\n}"

            let filesDict: String = fileParts.isEmpty ? "{}" :
                "{\n" + fileParts.map { p -> String in
                    if let s = p.fileURL, let u = URL(string: s) {
                        return "    \(pyString(p.name)): open(\(pyString(u.path)), \"rb\")"
                    }
                    return "    \(pyString(p.name)): open(\"<no file>\", \"rb\")"
                }.joined(separator: ",\n") + "\n}"

            lines.append("response = requests.request(")
            lines.append("    method=\(method),")
            lines.append("    url=\(url),")
            lines.append("    headers=\(headersBlock),")
            lines.append("    data=\(dataDict),")
            lines.append("    files=\(filesDict),")
            lines.append(")")

        case .json:
            let body: String
            if let b64 = draft.bodyBase64, !b64.isEmpty,
               let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                body = s.isEmpty ? "None" : "json=\(s)"
            } else {
                body = "json=None"
            }
            lines.append("response = requests.request(")
            lines.append("    method=\(method),")
            lines.append("    url=\(url),")
            lines.append("    headers=\(headersBlock),")
            lines.append("    \(body),")
            lines.append(")")

        default:
            let bodyExpr: String
            if let b64 = draft.bodyBase64, !b64.isEmpty,
               let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                bodyExpr = "data=\(pyString(s))"
            } else if (draft.bodyBase64?.isEmpty == false) {
                bodyExpr = "# binary body — replace with bytes\n    data=b\"\""
            } else {
                bodyExpr = "data=None"
            }
            lines.append("response = requests.request(")
            lines.append("    method=\(method),")
            lines.append("    url=\(url),")
            lines.append("    headers=\(headersBlock),")
            lines.append("    \(bodyExpr),")
            lines.append(")")
        }

        lines.append("print(response.status_code)")
        lines.append("print(response.text)")
        return lines.joined(separator: "\n")
    }

    /// Python double-quoted string with proper escapes.
    private static func pyString(_ s: String) -> String {
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
        return out
    }
}

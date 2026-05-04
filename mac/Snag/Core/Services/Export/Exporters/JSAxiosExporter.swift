import Foundation

/// `axios.request({...})` snippet. Multipart uses `FormData` (browser & Node 18+).
enum JSAxiosExporter: RequestExporter {

    static func export(_ draft: RequestDraftData) -> String {
        var lines: [String] = ["import axios from \"axios\";", ""]

        let url = JSFetchExporter.jsString(draft.rebuildURL())
        let method = JSFetchExporter.jsString(draft.method.uppercased())

        let headerPairs: [String] = draft.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .filter { !($0.key.caseInsensitiveCompare("Content-Type") == .orderedSame &&
                        draft.bodyEncoding == .multipart) }
            .map { "    \(JSFetchExporter.jsString($0.key)): \(JSFetchExporter.jsString($0.value))" }

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
                    lines.append("form.append(\(JSFetchExporter.jsString(p.name)), \(JSFetchExporter.jsString(p.textValue)));")
                case .file:
                    lines.append("form.append(\(JSFetchExporter.jsString(p.name)), /* fs.createReadStream(path) | File */ null);")
                }
            }
            lines.append("")
            lines.append("const response = await axios.request({")
            lines.append("  method: \(method),")
            lines.append("  url: \(url),")
            lines.append("  headers: \(headersBlock),")
            lines.append("  data: form,")
            lines.append("});")

        case .json:
            let bodyValue: String
            if let b64 = draft.bodyBase64, !b64.isEmpty,
               let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                bodyValue = s.isEmpty ? "undefined" : s
            } else {
                bodyValue = "undefined"
            }
            lines.append("const response = await axios.request({")
            lines.append("  method: \(method),")
            lines.append("  url: \(url),")
            lines.append("  headers: \(headersBlock),")
            lines.append("  data: \(bodyValue),")
            lines.append("});")

        default:
            let bodyValue: String
            if let b64 = draft.bodyBase64, !b64.isEmpty,
               let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                bodyValue = JSFetchExporter.jsString(s)
            } else if (draft.bodyBase64?.isEmpty == false) {
                bodyValue = "/* binary body — Buffer.from(...) */ undefined"
            } else {
                bodyValue = "undefined"
            }
            lines.append("const response = await axios.request({")
            lines.append("  method: \(method),")
            lines.append("  url: \(url),")
            lines.append("  headers: \(headersBlock),")
            lines.append("  data: \(bodyValue),")
            lines.append("});")
        }

        lines.append("console.log(response.status, response.data);")
        return lines.joined(separator: "\n")
    }
}

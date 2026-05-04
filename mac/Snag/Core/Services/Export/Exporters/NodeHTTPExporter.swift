import Foundation

/// Node `http`/`https` module snippet. Picks `https` for TLS hosts.
enum NodeHTTPExporter: RequestExporter {

    static func export(_ draft: RequestDraftData) -> String {
        let urlStr = draft.rebuildURL()
        let url = URL(string: urlStr)
        let isTLS = (url?.scheme ?? "").lowercased() == "https"
        let host = url?.host ?? ""
        let port: Int = url?.port ?? (isTLS ? 443 : 80)
        let path: String = {
            guard let url else { return "/" }
            var p = url.path.isEmpty ? "/" : url.path
            if let q = url.query, !q.isEmpty { p += "?\(q)" }
            return p
        }()
        let module = isTLS ? "https" : "http"

        let headerPairs: [String] = draft.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .filter { !($0.key.caseInsensitiveCompare("Content-Type") == .orderedSame &&
                        draft.bodyEncoding == .multipart) }
            .map { "    \(JSFetchExporter.jsString($0.key)): \(JSFetchExporter.jsString($0.value))" }

        let headersBlock: String =
            headerPairs.isEmpty
                ? "{}"
                : "{\n\(headerPairs.joined(separator: ",\n"))\n  }"

        var lines: [String] = []
        lines.append("const \(module) = require(\(JSFetchExporter.jsString(module)));")
        lines.append("")
        lines.append("const options = {")
        lines.append("  host: \(JSFetchExporter.jsString(host)),")
        lines.append("  port: \(port),")
        lines.append("  path: \(JSFetchExporter.jsString(path)),")
        lines.append("  method: \(JSFetchExporter.jsString(draft.method.uppercased())),")
        lines.append("  headers: \(headersBlock),")
        lines.append("};")
        lines.append("")
        lines.append("const req = \(module).request(options, (res) => {")
        lines.append("  let data = \"\";")
        lines.append("  res.on(\"data\", (chunk) => { data += chunk; });")
        lines.append("  res.on(\"end\", () => { console.log(res.statusCode, data); });")
        lines.append("});")
        lines.append("")

        if draft.bodyEncoding == .multipart {
            lines.append("// Multipart bodies need a multipart encoder (e.g. `form-data`).")
        } else if let b64 = draft.bodyBase64, !b64.isEmpty {
            if let data = Data(base64Encoded: b64),
               let s = String(data: data, encoding: .utf8) {
                lines.append("req.write(\(JSFetchExporter.jsString(s)));")
            } else {
                lines.append("req.write(Buffer.from(\(JSFetchExporter.jsString(b64)), \"base64\"));")
            }
        }
        lines.append("req.end();")
        return lines.joined(separator: "\n")
    }
}

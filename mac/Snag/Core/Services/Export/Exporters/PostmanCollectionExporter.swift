import Foundation

/// Serializes drafts as a Postman Collection v2.1 document. The collection is
/// flat — all requests live directly under `info` with no folder structure,
/// since drafts have no native folder hierarchy yet.
enum PostmanCollectionExporter: BulkRequestExporter {

    static func export(_ drafts: [RequestDraftData]) -> String {
        let items: [[String: Any]] = drafts.map { item(for: $0) }
        let now = ISO8601DateFormatter().string(from: Date())

        let info: [String: Any] = [
            "name": "Snag Export — \(now)",
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
            "_postman_id": UUID().uuidString
        ]
        let root: [String: Any] = [
            "info": info,
            "item": items
        ]

        let data = (try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func item(for d: RequestDraftData) -> [String: Any] {
        var entry: [String: Any] = [
            "name": d.displayName,
            "request": request(for: d)
        ]
        // Postman uses `response` as an array of saved examples — leave empty.
        entry["response"] = []
        return entry
    }

    private static func request(for d: RequestDraftData) -> [String: Any] {
        var dict: [String: Any] = [
            "method": d.method.uppercased(),
            "url": urlObject(for: d),
            "header": d.headers
                .filter { !$0.key.isEmpty }
                .map { kv -> [String: Any] in
                    var h: [String: Any] = ["key": kv.key, "value": kv.value]
                    if !kv.enabled { h["disabled"] = true }
                    return h
                }
        ]
        if let body = body(for: d) {
            dict["body"] = body
        }
        return dict
    }

    private static func urlObject(for d: RequestDraftData) -> [String: Any] {
        let raw = d.rebuildURL()
        guard let comps = URLComponents(string: raw) else {
            return ["raw": raw]
        }
        var obj: [String: Any] = ["raw": raw]
        if let scheme = comps.scheme { obj["protocol"] = scheme }
        if let host = comps.host {
            obj["host"] = host.split(separator: ".").map(String.init)
        }
        if let port = comps.port { obj["port"] = String(port) }
        let pathParts = comps.path.split(separator: "/").map(String.init)
        if !pathParts.isEmpty { obj["path"] = pathParts }
        if let q = comps.queryItems, !q.isEmpty {
            obj["query"] = q.map { ["key": $0.name, "value": $0.value ?? ""] }
        }
        return obj
    }

    private static func body(for d: RequestDraftData) -> [String: Any]? {
        if d.bodyEncoding == .multipart {
            let formdata: [[String: Any]] = d.multipartParts
                .filter { !$0.name.isEmpty }
                .map { p in
                    var entry: [String: Any] = ["key": p.name]
                    if !p.enabled { entry["disabled"] = true }
                    switch p.kind {
                    case .text:
                        entry["type"] = "text"
                        entry["value"] = p.textValue
                    case .file:
                        entry["type"] = "file"
                        if let s = p.fileURL { entry["src"] = s }
                        if let ct = p.contentType, !ct.isEmpty { entry["contentType"] = ct }
                    }
                    return entry
                }
            return ["mode": "formdata", "formdata": formdata]
        }

        guard let b64 = d.bodyBase64, !b64.isEmpty,
              let data = Data(base64Encoded: b64) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? data.base64EncodedString()

        let isUrlencoded = (d.bodyContentType ?? "")
            .lowercased()
            .contains("application/x-www-form-urlencoded")
        if isUrlencoded {
            let pairs = text.split(separator: "&").compactMap { pair -> [String: String]? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard let key = parts.first else { return nil }
                return ["key": key, "value": parts.count > 1 ? parts[1] : ""]
            }
            return ["mode": "urlencoded", "urlencoded": pairs]
        }

        let language = (d.bodyEncoding == .json) ? "json" : "text"
        return [
            "mode": "raw",
            "raw": text,
            "options": ["raw": ["language": language]]
        ]
    }
}

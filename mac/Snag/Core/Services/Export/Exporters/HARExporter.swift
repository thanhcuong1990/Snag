import Foundation

/// Serializes one or more drafts as an HTTP Archive (HAR 1.2) document.
/// HAR is response-centric, but Snag exports request-only — `entries[*].response`
/// is a minimal stub since the source draft has no committed run output.
enum HARExporter: BulkRequestExporter {

    static func export(_ drafts: [RequestDraftData]) -> String {
        let entries: [[String: Any]] = drafts.map { entry(for: $0) }

        let log: [String: Any] = [
            "version": "1.2",
            "creator": ["name": "Snag", "version": appVersion()],
            "entries": entries,
            "pages": []
        ]
        let root: [String: Any] = ["log": log]

        let data = (try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func entry(for d: RequestDraftData) -> [String: Any] {
        let url = d.rebuildURL()
        let request = harRequest(d, url: url)
        let now = ISO8601DateFormatter().string(from: Date())
        return [
            "startedDateTime": now,
            "time": 0,
            "request": request,
            "response": emptyResponse(),
            "cache": [:],
            "timings": ["send": 0, "wait": 0, "receive": 0]
        ]
    }

    private static func harRequest(_ d: RequestDraftData, url: String) -> [String: Any] {
        var headers: [[String: String]] = d.headers
            .filter { $0.enabled && !$0.key.isEmpty }
            .map { ["name": $0.key, "value": $0.value] }

        // For multipart, advertise the content type so consumers can re-parse.
        if d.bodyEncoding == .multipart,
           !headers.contains(where: { ($0["name"] ?? "").caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headers.append(["name": "Content-Type", "value": "multipart/form-data"])
        }

        let queryString: [[String: String]] = RequestDraftData
            .parseQueryItems(from: url)
            .map { ["name": $0.key, "value": $0.value] }

        var dict: [String: Any] = [
            "method": d.method.uppercased(),
            "url": url,
            "httpVersion": "HTTP/1.1",
            "headers": headers,
            "queryString": queryString,
            "cookies": [],
            "headersSize": -1,
            "bodySize": -1
        ]

        if let post = postData(d) {
            dict["postData"] = post
        }
        return dict
    }

    private static func postData(_ d: RequestDraftData) -> [String: Any]? {
        if d.bodyEncoding == .multipart {
            let params: [[String: Any]] = d.multipartParts
                .filter { $0.enabled && !$0.name.isEmpty }
                .map { p in
                    var entry: [String: Any] = ["name": p.name]
                    switch p.kind {
                    case .text:
                        entry["value"] = p.textValue
                    case .file:
                        if let fn = p.fileName, !fn.isEmpty { entry["fileName"] = fn }
                        else if let s = p.fileURL, let u = URL(string: s) {
                            entry["fileName"] = u.lastPathComponent
                        }
                        if let ct = p.contentType, !ct.isEmpty { entry["contentType"] = ct }
                    }
                    return entry
                }
            return [
                "mimeType": "multipart/form-data",
                "params": params
            ]
        }

        guard let b64 = d.bodyBase64,
              !b64.isEmpty,
              let data = Data(base64Encoded: b64) else { return nil }
        let mime = d.bodyContentType ?? (d.bodyEncoding == .json ? "application/json" : "text/plain")
        let text = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        return [
            "mimeType": mime,
            "text": text
        ]
    }

    private static func emptyResponse() -> [String: Any] {
        [
            "status": 0,
            "statusText": "",
            "httpVersion": "HTTP/1.1",
            "cookies": [],
            "headers": [],
            "content": ["size": 0, "mimeType": ""],
            "redirectURL": "",
            "headersSize": -1,
            "bodySize": -1
        ]
    }

    private static func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
}

import Foundation

/// HTTP Archive (HAR) importer. Each `log.entries[*].request` becomes one
/// `ImportableRequest`. HAR has no folder structure, so the batch's
/// `folders` is `nil` (flat list).
enum HARImporter: BatchImporter {

    static func canHandle(_ input: ImportInput) -> Bool {
        guard let text = try? input.readText() else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "{" &&
               trimmed.contains("\"log\"") &&
               trimmed.contains("\"entries\"")
    }

    static func parse(_ input: ImportInput,
                      options: CurlImportOptions) throws -> ImportableBatch {
        let text = try input.readText()
        guard let data = text.data(using: .utf8) else {
            throw ImportError.malformedJSON("not utf-8")
        }

        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data, options: []) }
        catch { throw ImportError.malformedJSON(error.localizedDescription) }

        guard let root = json as? [String: Any],
              let log = root["log"] as? [String: Any],
              let entries = log["entries"] as? [[String: Any]] else {
            throw ImportError.malformedJSON("log.entries missing")
        }

        var requests: [ImportableRequest] = []
        for (i, entry) in entries.enumerated() {
            guard let req = entry["request"] as? [String: Any] else { continue }
            if let r = parseEntry(req, index: i) {
                requests.append(r)
            }
        }

        if requests.isEmpty { throw ImportError.emptyBatch }

        return ImportableBatch(
            sourceLabel: input.label,
            requests: requests,
            folders: nil
        )
    }

    private static func parseEntry(_ req: [String: Any], index: Int) -> ImportableRequest? {
        guard let url = req["url"] as? String else { return nil }
        let method = (req["method"] as? String) ?? "GET"

        var warnings: [String] = []

        var headers: [DraftKeyValue] = []
        if let arr = req["headers"] as? [[String: Any]] {
            for h in arr {
                guard let name = h["name"] as? String else { continue }
                let value = (h["value"] as? String) ?? ""
                if name.hasPrefix(":") { continue } // HTTP/2 pseudo-headers
                headers.append(DraftKeyValue(key: name, value: value))
            }
        }

        // HAR cookies → Cookie header (avoid storing them twice).
        if let cookies = req["cookies"] as? [[String: Any]], !cookies.isEmpty,
           !headers.contains(where: { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }) {
            let pairs = cookies.compactMap { c -> String? in
                guard let n = c["name"] as? String, let v = c["value"] as? String else { return nil }
                return "\(n)=\(v)"
            }
            if !pairs.isEmpty {
                headers.append(DraftKeyValue(key: "Cookie", value: pairs.joined(separator: "; ")))
            }
        }

        let queryParams: [DraftKeyValue]
        if let arr = req["queryString"] as? [[String: Any]], !arr.isEmpty {
            queryParams = arr.compactMap { q in
                guard let n = q["name"] as? String else { return nil }
                let v = (q["value"] as? String) ?? ""
                return DraftKeyValue(key: n, value: v)
            }
        } else {
            queryParams = RequestDraftData.parseQueryItems(from: url)
        }

        let (bodyBase64, encoding, contentType, multipart) =
            parsePostData(req["postData"] as? [String: Any], warnings: &warnings)

        let path = URL(string: url)?.path ?? url
        let synthName = "\(method) \(path)"
        var data = RequestDraftData(
            name: synthName,
            url: url,
            method: method,
            headers: headers,
            queryParams: queryParams,
            bodyBase64: bodyBase64,
            bodyEncoding: encoding,
            bodyContentType: contentType,
            multipartParts: multipart
        )
        data.url = data.rebuildURL()

        return ImportableRequest(
            folderPath: [],
            name: synthName,
            draftData: data,
            warnings: warnings
        )
    }

    private static func parsePostData(_ post: [String: Any]?, warnings: inout [String])
        -> (String?, BodyEncoding, String?, [DraftMultipartPart])
    {
        guard let post else { return (nil, .text, nil, []) }

        let mime = (post["mimeType"] as? String) ?? ""

        if mime.lowercased().contains("multipart/form-data") {
            let arr = (post["params"] as? [[String: Any]]) ?? []
            let parts = arr.compactMap { p -> DraftMultipartPart? in
                guard let name = p["name"] as? String else { return nil }
                if let fileName = p["fileName"] as? String, !fileName.isEmpty {
                    return DraftMultipartPart(
                        name: name, kind: .file,
                        fileName: fileName,
                        contentType: p["contentType"] as? String
                    )
                }
                let v = (p["value"] as? String) ?? ""
                return DraftMultipartPart(name: name, kind: .text, textValue: v)
            }
            return (nil, .multipart, nil, parts)
        }

        if mime.lowercased().contains("urlencoded") {
            if let text = post["text"] as? String {
                return (Data(text.utf8).base64EncodedString(),
                        .text, "application/x-www-form-urlencoded", [])
            }
            let arr = (post["params"] as? [[String: Any]]) ?? []
            let pairs = arr.compactMap { p -> String? in
                guard let n = p["name"] as? String else { return nil }
                let v = (p["value"] as? String) ?? ""
                return "\(n)=\(v)"
            }
            return (Data(pairs.joined(separator: "&").utf8).base64EncodedString(),
                    .text, "application/x-www-form-urlencoded", [])
        }

        if let text = post["text"] as? String, !text.isEmpty {
            let enc: BodyEncoding = mime.lowercased().contains("json") ? .json : .text
            return (Data(text.utf8).base64EncodedString(), enc, mime.isEmpty ? nil : mime, [])
        }

        return (nil, .text, nil, [])
    }
}

import Foundation

/// Postman Collection v2.1 / v2.0 importer. Walks `item[]` recursively and
/// produces one `ImportableRequest` per leaf request, with a folder tree built
/// from the parent `item` (folder) chain.
enum PostmanCollectionImporter: BatchImporter {

    static func canHandle(_ input: ImportInput) -> Bool {
        guard let text = try? input.readText() else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "{" &&
               trimmed.contains("\"info\"") &&
               trimmed.contains("\"item\"")
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

        guard let root = json as? [String: Any] else {
            throw ImportError.malformedJSON("root is not an object")
        }

        if let info = root["info"] as? [String: Any],
           let schema = info["schema"] as? String,
           !(schema.contains("v2.1.0") || schema.contains("v2.0.0")) {
            // Unknown schema — try anyway, but warn at the top level.
        }

        var requests: [ImportableRequest] = []
        let rootName = (root["info"] as? [String: Any])?["name"] as? String ?? input.label
        let rootItems = (root["item"] as? [[String: Any]]) ?? []

        var rootNode = FolderNode(name: rootName)
        walkPostman(items: rootItems, into: &rootNode, path: [], requests: &requests)

        if requests.isEmpty { throw ImportError.emptyBatch }

        return ImportableBatch(
            sourceLabel: input.label,
            requests: requests,
            folders: rootNode
        )
    }

    /// `path` is the chain of folder names from (but not including) the root
    /// down to the current `node` — so a request directly under the root has
    /// `folderPath == []`, not `[rootName]`.
    private static func walkPostman(items: [[String: Any]],
                                    into node: inout FolderNode,
                                    path: [String],
                                    requests: inout [ImportableRequest]) {
        for item in items {
            let name = (item["name"] as? String) ?? "Unnamed"
            if let children = item["item"] as? [[String: Any]] {
                var child = FolderNode(name: name)
                walkPostman(items: children, into: &child, path: path + [name], requests: &requests)
                node.children.append(child)
            } else if let req = item["request"] {
                if let parsed = parseRequest(req, name: name, folderPath: path) {
                    node.requestIDs.append(parsed.id)
                    requests.append(parsed)
                }
            }
        }
    }

    private static func parseRequest(_ raw: Any,
                                     name: String,
                                     folderPath: [String]) -> ImportableRequest? {
        // Postman allows `request` to be a string ("GET https://…") or an object.
        if let s = raw as? String {
            if let result = try? CurlImporter.parse("curl \(s)") {
                return ImportableRequest(
                    folderPath: folderPath,
                    name: name,
                    draftData: result.draft,
                    warnings: result.warnings
                )
            }
            return nil
        }

        guard let obj = raw as? [String: Any] else { return nil }
        var warnings: [String] = []

        let method = (obj["method"] as? String) ?? "GET"
        let url = postmanURL(obj["url"], warnings: &warnings)
        let headers = postmanHeaders(obj["header"])
        let (bodyBase64, bodyEncoding, bodyContentType, multipart) =
            postmanBody(obj["body"], warnings: &warnings)
        let authHeader = postmanAuthHeader(obj["auth"], warnings: &warnings)

        var allHeaders = headers
        if let auth = authHeader,
           !allHeaders.contains(where: { $0.key.caseInsensitiveCompare("Authorization") == .orderedSame }) {
            allHeaders.append(auth)
        }

        var data = RequestDraftData(
            name: name,
            url: url,
            method: method,
            headers: allHeaders,
            queryParams: RequestDraftData.parseQueryItems(from: url),
            bodyBase64: bodyBase64,
            bodyEncoding: bodyEncoding,
            bodyContentType: bodyContentType,
            multipartParts: multipart
        )
        data.url = data.rebuildURL()

        return ImportableRequest(
            folderPath: folderPath,
            name: name,
            draftData: data,
            warnings: warnings
        )
    }

    // MARK: - URL

    private static func postmanURL(_ raw: Any?, warnings: inout [String]) -> String {
        if let s = raw as? String { return resolvePlaceholders(s, warnings: &warnings) }
        guard let obj = raw as? [String: Any] else { return "" }

        // Prefer `raw` when present — it preserves user formatting.
        if let s = obj["raw"] as? String { return resolvePlaceholders(s, warnings: &warnings) }

        var rebuilt = ""
        if let protocolStr = obj["protocol"] as? String { rebuilt += protocolStr + "://" }
        if let hosts = obj["host"] as? [String] {
            rebuilt += hosts.joined(separator: ".")
        } else if let h = obj["host"] as? String {
            rebuilt += h
        }
        if let port = obj["port"] as? String, !port.isEmpty { rebuilt += ":" + port }
        if let paths = obj["path"] as? [String] {
            if !paths.isEmpty { rebuilt += "/" + paths.joined(separator: "/") }
        } else if let p = obj["path"] as? String, !p.isEmpty {
            rebuilt += "/" + p
        }
        if let q = obj["query"] as? [[String: Any]], !q.isEmpty {
            let pairs = q.compactMap { kv -> String? in
                guard let k = kv["key"] as? String else { return nil }
                let v = (kv["value"] as? String) ?? ""
                return "\(k)=\(v)"
            }
            if !pairs.isEmpty { rebuilt += "?" + pairs.joined(separator: "&") }
        }
        return resolvePlaceholders(rebuilt, warnings: &warnings)
    }

    /// Pass `{{var}}` placeholders through literally; surface a warning so the
    /// user knows to fill them in after import.
    private static func resolvePlaceholders(_ s: String, warnings: inout [String]) -> String {
        if s.contains("{{") {
            warnings.append("Unresolved Postman variable in: \(s)")
        }
        return s
    }

    // MARK: - Headers

    private static func postmanHeaders(_ raw: Any?) -> [DraftKeyValue] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap {
            guard let k = $0["key"] as? String else { return nil }
            let v = ($0["value"] as? String) ?? ""
            let disabled = ($0["disabled"] as? Bool) ?? false
            return DraftKeyValue(key: k, value: v, enabled: !disabled)
        }
    }

    // MARK: - Body

    private static func postmanBody(_ raw: Any?, warnings: inout [String])
        -> (String?, BodyEncoding, String?, [DraftMultipartPart])
    {
        guard let body = raw as? [String: Any] else { return (nil, .text, nil, []) }

        let mode = (body["mode"] as? String) ?? ""
        switch mode {
        case "raw":
            let raw = (body["raw"] as? String) ?? ""
            let lang = ((body["options"] as? [String: Any])?["raw"] as? [String: Any])?["language"] as? String
            let enc: BodyEncoding = (lang == "json") ? .json : .text
            return (Data(raw.utf8).base64EncodedString(), enc, nil, [])

        case "urlencoded":
            let arr = (body["urlencoded"] as? [[String: Any]]) ?? []
            let pairs = arr.compactMap { p -> String? in
                guard let k = p["key"] as? String else { return nil }
                let v = (p["value"] as? String) ?? ""
                return "\(k)=\(v)"
            }
            return (Data(pairs.joined(separator: "&").utf8).base64EncodedString(),
                    .text, "application/x-www-form-urlencoded", [])

        case "formdata":
            let arr = (body["formdata"] as? [[String: Any]]) ?? []
            let parts = arr.compactMap { p -> DraftMultipartPart? in
                guard let key = p["key"] as? String else { return nil }
                let kindStr = (p["type"] as? String) ?? "text"
                let disabled = (p["disabled"] as? Bool) ?? false
                if kindStr == "file" {
                    let src = p["src"] as? String
                    return DraftMultipartPart(
                        name: key,
                        kind: .file,
                        fileURL: src,
                        contentType: p["contentType"] as? String,
                        enabled: !disabled
                    )
                } else {
                    let val = (p["value"] as? String) ?? ""
                    return DraftMultipartPart(name: key, kind: .text, textValue: val, enabled: !disabled)
                }
            }
            return (nil, .multipart, nil, parts)

        case "graphql":
            let g = body["graphql"] as? [String: Any] ?? [:]
            let query = (g["query"] as? String) ?? ""
            let vars = g["variables"]
            let payload: [String: Any] = [
                "query": query,
                "variables": vars ?? NSNull()
            ]
            if let json = try? JSONSerialization.data(withJSONObject: payload),
               let s = String(data: json, encoding: .utf8) {
                return (Data(s.utf8).base64EncodedString(), .json, "application/json", [])
            }
            return (Data(query.utf8).base64EncodedString(), .json, "application/json", [])

        case "file":
            warnings.append("Postman 'file' body mode: Snag couldn't resolve the file path; multipart left empty.")
            return (nil, .multipart, nil, [])

        default:
            return (nil, .text, nil, [])
        }
    }

    private static func postmanAuthHeader(_ raw: Any?, warnings: inout [String]) -> DraftKeyValue? {
        guard let auth = raw as? [String: Any] else { return nil }
        let type = (auth["type"] as? String) ?? ""

        switch type {
        case "basic":
            let arr = (auth["basic"] as? [[String: Any]]) ?? []
            let user = arr.first { ($0["key"] as? String) == "username" }?["value"] as? String ?? ""
            let pass = arr.first { ($0["key"] as? String) == "password" }?["value"] as? String ?? ""
            let encoded = Data("\(user):\(pass)".utf8).base64EncodedString()
            return DraftKeyValue(key: "Authorization", value: "Basic \(encoded)")

        case "bearer":
            let arr = (auth["bearer"] as? [[String: Any]]) ?? []
            let token = arr.first { ($0["key"] as? String) == "token" }?["value"] as? String ?? ""
            return DraftKeyValue(key: "Authorization", value: "Bearer \(token)")

        case "":
            return nil

        default:
            warnings.append("Unsupported Postman auth type: \(type)")
            return nil
        }
    }
}

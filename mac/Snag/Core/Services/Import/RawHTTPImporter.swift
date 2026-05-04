import Foundation

/// Parses a raw HTTP/1.1 wire-format request into a single `ImportableBatch`.
/// Format:
///
///     METHOD path HTTP/1.1
///     Header-A: value-a
///     Header-B: value-b
///     <blank line>
///     <body>
///
/// Tolerates LF-only line endings and uses the `Host` header to reconstruct
/// the absolute URL.
enum RawHTTPImporter: BatchImporter {

    static func canHandle(_ input: ImportInput) -> Bool {
        guard let text = try? input.readText() else { return false }
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        // First line must look like `METHOD path HTTP/1.x`.
        let parts = trimmed.split(separator: " ").map(String.init)
        return parts.count >= 3 &&
               parts[2].uppercased().hasPrefix("HTTP/")
    }

    static func parse(_ input: ImportInput,
                      options: CurlImportOptions) throws -> ImportableBatch {
        let text = try input.readText()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        let halves = normalized.components(separatedBy: "\n\n")
        let head = halves.first ?? normalized
        let body = halves.count > 1 ? halves.dropFirst().joined(separator: "\n\n") : ""

        let lines = head.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            throw ImportError.malformedJSON("empty input")
        }
        let parts = requestLine.split(separator: " ").map(String.init)
        guard parts.count >= 3 else {
            throw ImportError.malformedJSON("invalid request line: \(requestLine)")
        }

        let method = parts[0].uppercased()
        let target = parts[1]

        var headers: [DraftKeyValue] = []
        var hostHeader: String?
        var contentType: String?
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if key.isEmpty { continue }
            if key.caseInsensitiveCompare("Host") == .orderedSame {
                hostHeader = value
            }
            if key.caseInsensitiveCompare("Content-Type") == .orderedSame {
                contentType = value
            }
            headers.append(DraftKeyValue(key: key, value: value))
        }

        let url: String
        if target.lowercased().hasPrefix("http://") || target.lowercased().hasPrefix("https://") {
            url = target
        } else if let host = hostHeader {
            // Default to https:// — most modern hosts redirect anyway, and the
            // user can flip to http:// after import if needed.
            url = "https://\(host)\(target.hasPrefix("/") ? target : "/\(target)")"
        } else {
            url = target
        }

        let bodyBytes = body
        let bodyEncoding: BodyEncoding = {
            if let ct = contentType?.lowercased(), ct.contains("json") { return .json }
            return .text
        }()
        let bodyBase64: String? = bodyBytes.isEmpty ? nil : Data(bodyBytes.utf8).base64EncodedString()

        var data = RequestDraftData(
            name: "\(method) \(target)",
            url: url,
            method: method,
            headers: headers,
            queryParams: RequestDraftData.parseQueryItems(from: url),
            bodyBase64: bodyBase64,
            bodyEncoding: bodyEncoding,
            bodyContentType: contentType
        )
        data.url = data.rebuildURL()

        let req = ImportableRequest(
            folderPath: [],
            name: data.name,
            draftData: data,
            warnings: []
        )
        return ImportableBatch(
            sourceLabel: input.label,
            requests: [req],
            folders: nil
        )
    }
}

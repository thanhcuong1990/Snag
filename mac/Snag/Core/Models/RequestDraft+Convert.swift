import Foundation
import UniformTypeIdentifiers

extension RequestDraftData {

    /// Build a draft from a captured packet. Captured headers are `[String: String]` upstream,
    /// so duplicate header keys are already collapsed at capture time and cannot be recovered.
    static func from(_ packet: SnagPacket) -> RequestDraftData {
        let info = packet.requestInfo
        let url = info?.url ?? ""
        let method = info?.requestMethod?.rawValue ?? "GET"

        let headerRows: [DraftKeyValue] = (info?.requestHeaders ?? [:])
            .sorted(by: { $0.key < $1.key })
            .map { DraftKeyValue(key: $0.key, value: $0.value) }

        let queryRows: [DraftKeyValue] = parseQueryItems(from: url)

        // Capture body as the same base64 the packet stores; binary-safe.
        let body = info?.requestBody
        let contentType = info?.requestContentType
        let encoding: BodyEncoding = {
            guard let ct = contentType?.lowercased() else { return .text }
            if ct.contains("json") { return .json }
            if ct.contains("text") || ct.contains("xml") || ct.contains("urlencoded") || ct.contains("javascript") {
                return .text
            }
            return .base64
        }()

        return RequestDraftData(
            url: url,
            method: method,
            headers: headerRows,
            queryParams: queryRows,
            bodyBase64: body,
            bodyEncoding: encoding,
            bodyContentType: contentType
        )
    }

    static func parseQueryItems(from urlString: String) -> [DraftKeyValue] {
        guard let comps = URLComponents(string: urlString) else { return [] }
        return (comps.queryItems ?? []).map {
            DraftKeyValue(key: $0.name, value: $0.value ?? "")
        }
    }

    /// URL with the query stripped (scheme + host + path only). Used when query is edited
    /// and the URL has to be rebuilt from `queryParams`.
    var urlWithoutQuery: String {
        guard var comps = URLComponents(string: url) else { return url }
        comps.queryItems = nil
        comps.fragment = nil
        return comps.string ?? url
    }

    /// Rebuild the full URL from the base + enabled queryParams. Preserves order.
    func rebuildURL() -> String {
        guard var comps = URLComponents(string: url) else { return url }
        let enabled = queryParams.filter { $0.enabled && !$0.key.isEmpty }
        comps.queryItems = enabled.isEmpty ? nil : enabled.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        return comps.string ?? url
    }

    /// Build a `URLRequest` ready for `RequestSender.send`. Throws `DraftValidationError`
    /// for any user-recoverable issue.
    func toURLRequest() throws -> URLRequest {
        let resolvedURLString = rebuildURL()
        guard let url = URL(string: resolvedURLString) else {
            throw DraftValidationError.invalidURL
        }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw DraftValidationError.invalidScheme(url.scheme ?? "")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method.uppercased()
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = max(1, timeoutSeconds)

        let isMultipart = (bodyEncoding == .multipart)

        for h in headers where h.enabled && !h.key.isEmpty {
            // RFC 7230 forbids CR/LF in field values.
            if h.key.rangeOfCharacter(from: .newlines) != nil ||
               h.value.rangeOfCharacter(from: .newlines) != nil {
                throw DraftValidationError.invalidHeader(h.key)
            }
            // Multipart auto-sets its own Content-Type with boundary; skip any user-set one.
            if isMultipart, h.key.caseInsensitiveCompare("Content-Type") == .orderedSame {
                continue
            }
            req.setValue(h.value, forHTTPHeaderField: h.key)
        }

        if isMultipart {
            let (data, contentType) = try Self.buildMultipartBody(parts: multipartParts)
            guard data.count <= 50 * 1024 * 1024 else {
                throw DraftValidationError.bodyTooLarge
            }
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = data
        } else if let bodyBase64 = bodyBase64,
                  !bodyBase64.isEmpty,
                  let data = Data(base64Encoded: bodyBase64) {
            // 10 MB editor cap — anything larger is unsupported in v1.
            guard data.count <= 10 * 1024 * 1024 else {
                throw DraftValidationError.bodyTooLarge
            }
            req.httpBody = data
        }

        return req
    }

    /// Encode the enabled parts as RFC 7578 `multipart/form-data`.
    /// Returns `(body, contentType)` where the content-type already includes the boundary.
    static func buildMultipartBody(parts: [DraftMultipartPart],
                                   boundary: String = "Boundary-\(UUID().uuidString)") throws -> (Data, String) {
        var body = Data()
        let crlf = Data("\r\n".utf8)

        for part in parts where part.enabled && !part.name.isEmpty {
            body.append(Data("--\(boundary)\r\n".utf8))

            switch part.kind {
            case .text:
                body.append(Data("Content-Disposition: form-data; name=\"\(escapeFormDataValue(part.name))\"\r\n".utf8))
                if let ct = part.contentType, !ct.isEmpty {
                    body.append(Data("Content-Type: \(ct)\r\n".utf8))
                }
                body.append(crlf)
                body.append(Data(part.textValue.utf8))
                body.append(crlf)

            case .file:
                guard let urlString = part.fileURL,
                      let fileURL = URL(string: urlString),
                      fileURL.isFileURL else {
                    throw DraftValidationError.invalidHeader("multipart part \"\(part.name)\" has no file")
                }
                let data: Data
                do {
                    data = try Data(contentsOf: fileURL)
                } catch {
                    throw DraftValidationError.invalidHeader("multipart part \"\(part.name)\": \(error.localizedDescription)")
                }
                let filename = part.fileName?.nilIfEmpty ?? fileURL.lastPathComponent
                let ct = part.contentType?.nilIfEmpty ?? mimeType(for: fileURL)
                body.append(Data("Content-Disposition: form-data; name=\"\(escapeFormDataValue(part.name))\"; filename=\"\(escapeFormDataValue(filename))\"\r\n".utf8))
                body.append(Data("Content-Type: \(ct)\r\n".utf8))
                body.append(crlf)
                body.append(data)
                body.append(crlf)
            }
        }

        body.append(Data("--\(boundary)--\r\n".utf8))
        return (body, "multipart/form-data; boundary=\(boundary)")
    }

    /// Escape per RFC 7578 §4.2 — CR/LF/quote in form-data field names and filenames.
    private static func escapeFormDataValue(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: "")
         .replacingOccurrences(of: "\n", with: "")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func mimeType(for url: URL) -> String {
        if let utt = UTType(filenameExtension: url.pathExtension), let mime = utt.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

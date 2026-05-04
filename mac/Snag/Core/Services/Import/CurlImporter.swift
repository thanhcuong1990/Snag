import Foundation

enum CurlParseError: LocalizedError, Equatable {
    case notACurlCommand
    case unterminatedQuote
    case missingValue(flag: String)
    case noURL
    case invalidURL(String)
    case unsupported(String)
    case bodyTooLarge
    case localFileReferenceRequiresConsent(path: String)
    case localFileNotFound(path: String)

    var errorDescription: String? {
        switch self {
        case .notACurlCommand:
            return "Input is not a curl command.".localized
        case .unterminatedQuote:
            return "Unterminated quote in input.".localized
        case .missingValue(let flag):
            return "Flag \(flag) is missing a value.".localized
        case .noURL:
            return "No URL found in the curl command.".localized
        case .invalidURL(let s):
            return "Invalid URL: \(s)".localized
        case .unsupported(let what):
            return "Unsupported: \(what)".localized
        case .bodyTooLarge:
            return "Request body exceeds the size limit.".localized
        case .localFileReferenceRequiresConsent(let path):
            return "Loading local file \(path) requires explicit consent.".localized
        case .localFileNotFound(let path):
            return "Local file not found: \(path)".localized
        }
    }
}

/// Result of a cURL import: the draft plus any non-fatal warnings to surface.
struct CurlImportResult: Equatable {
    var draft: RequestDraftData
    var warnings: [String]
}

/// Options that control how cURL imports interpret semi-trusted input.
struct CurlImportOptions {
    /// When `true`, `@/path` body and `-F field=@/path` references are
    /// resolved by reading the local file. When `false`, the path is recorded
    /// as a warning and left unresolved.
    var loadLocalFiles: Bool = false
}

enum CurlImporter {

    /// Parse a single cURL command. Returns the draft plus warnings.
    /// Throws only on fatal errors (no URL, unterminated quote, not curl).
    static func parse(_ input: String,
                      options: CurlImportOptions = CurlImportOptions()) throws -> CurlImportResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CurlParseError.notACurlCommand }

        let tokens = try CurlTokenizer.tokenize(trimmed)
        guard let first = tokens.first?.lowercased(), first == "curl" else {
            throw CurlParseError.notACurlCommand
        }

        let parsed = CurlArgumentParser.parse(tokens)
        return try parsed.toImportResult(options: options)
    }
}

extension ParsedCurl {

    /// Project the parsed cURL onto a `RequestDraftData`. See plan §3.3.
    func toImportResult(options: CurlImportOptions) throws -> CurlImportResult {
        guard let rawURL = url, !rawURL.isEmpty else {
            throw CurlParseError.noURL
        }

        var warnings = self.warnings

        // ── URL split ────────────────────────────────────────────────────
        let baseURL: String
        var queryRows: [DraftKeyValue] = []
        if let comps = URLComponents(string: rawURL) {
            queryRows = (comps.queryItems ?? []).map {
                DraftKeyValue(key: $0.name, value: $0.value ?? "")
            }
            var stripped = comps
            stripped.queryItems = nil
            stripped.fragment = nil
            baseURL = stripped.string ?? rawURL
        } else {
            baseURL = rawURL
            warnings.append("URL could not be parsed; left as-is.")
        }

        // ── Headers (preserve user order, case as-typed) ─────────────────
        var headerRows: [DraftKeyValue] = headers.map {
            DraftKeyValue(key: $0.0, value: $0.1)
        }

        func hasHeader(_ name: String) -> Bool {
            headerRows.contains {
                $0.key.caseInsensitiveCompare(name) == .orderedSame
            }
        }

        // ── Synthesized headers — only if not user-set ───────────────────
        if let auth = basicAuth {
            let pair = "\(auth.user):\(auth.password ?? "")"
            let encoded = Data(pair.utf8).base64EncodedString()
            if !hasHeader("Authorization") {
                headerRows.append(DraftKeyValue(key: "Authorization",
                                                value: "Basic \(encoded)"))
            }
        }
        if let cookie = cookieValue, !hasHeader("Cookie") {
            headerRows.append(DraftKeyValue(key: "Cookie", value: cookie))
        }
        if compressed, !hasHeader("Accept-Encoding") {
            headerRows.append(DraftKeyValue(key: "Accept-Encoding",
                                            value: "gzip, deflate, br"))
        }

        // ── Form parts → multipart, or data chunks → body ────────────────
        var multipartParts: [DraftMultipartPart] = []
        var bodyBase64: String? = nil
        var bodyEncoding: BodyEncoding = .text
        var bodyContentType: String? = nil

        let isMultipart = !formParts.isEmpty
        let userContentType = headerRows.first {
            $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value

        if isMultipart {
            bodyEncoding = .multipart
            for f in formParts {
                multipartParts.append(buildMultipartPart(from: f,
                                                        options: options,
                                                        warnings: &warnings))
            }
        } else if !dataChunks.isEmpty {
            // -G: data becomes query string, no body sent.
            if getOverride {
                let extra = encodeDataChunksAsQuery(dataChunks)
                queryRows.append(contentsOf: extra)
            } else {
                let (data, encoding, ct) = buildBody(
                    chunks: dataChunks,
                    userContentType: userContentType,
                    options: options,
                    warnings: &warnings
                )
                bodyBase64 = data.base64EncodedString()
                bodyEncoding = encoding
                bodyContentType = ct

                // -d/--data without explicit Content-Type → urlencoded default.
                if !hasHeader("Content-Type"), let inferred = ct {
                    headerRows.append(DraftKeyValue(key: "Content-Type",
                                                    value: inferred))
                }
            }
        }

        // ── Method inference ─────────────────────────────────────────────
        let resolvedMethod: String = {
            if let m = method, !m.isEmpty { return m }
            if headOverride { return "HEAD" }
            if isMultipart { return "POST" }
            if !dataChunks.isEmpty && !getOverride { return "POST" }
            return "GET"
        }()

        // ── Build draft ──────────────────────────────────────────────────
        var draft = RequestDraftData(
            url: baseURL,
            method: resolvedMethod,
            headers: headerRows,
            queryParams: queryRows,
            bodyBase64: bodyBase64,
            bodyEncoding: bodyEncoding,
            bodyContentType: bodyContentType,
            multipartParts: multipartParts,
            // Default to true (don't flip false on absence of -L); cURL's default behavior
            // is no-redirect, but Postman/Proxyman/DevTools generators elide -L routinely.
            followRedirects: true,
            timeoutSeconds: maxTime ?? 30,
            allowInvalidCertificates: allowInsecure
        )

        // Re-fold queryParams onto the URL so `draft.url` matches the input.
        draft.url = draft.rebuildURL()

        return CurlImportResult(draft: draft, warnings: warnings)
    }

    // MARK: - Helpers

    private func buildMultipartPart(from f: ParsedFormPart,
                                    options: CurlImportOptions,
                                    warnings: inout [String]) -> DraftMultipartPart {
        // Strip ;type=… and ;filename=… modifiers from the value.
        let segments = splitFormValue(f.rawValue)
        let head = segments[0]
        var contentType: String? = nil
        var fileNameOverride: String? = nil
        for seg in segments.dropFirst() {
            if let eq = seg.firstIndex(of: "=") {
                let key = String(seg[..<eq]).lowercased()
                let val = String(seg[seg.index(after: eq)...])
                if key == "type" {
                    contentType = val
                } else if key == "filename" {
                    fileNameOverride = val
                }
            }
        }

        if f.allowFileRef, head.hasPrefix("@") {
            let path = String(head.dropFirst())
            if path == "-" {
                warnings.append("-F \(f.name)=@-: stdin upload is not supported; part is empty.")
                return DraftMultipartPart(name: f.name, kind: .text, textValue: "")
            }
            if options.loadLocalFiles {
                let url = URL(fileURLWithPath: path)
                return DraftMultipartPart(
                    name: f.name,
                    kind: .file,
                    fileURL: url.absoluteString,
                    fileName: fileNameOverride,
                    contentType: contentType
                )
            } else {
                warnings.append(
                    "-F \(f.name)=@\(path): local file reference requires consent; part left empty. " +
                    "Re-import with \"Load local files\" enabled to attach."
                )
                return DraftMultipartPart(
                    name: f.name,
                    kind: .file,
                    fileURL: nil,
                    fileName: fileNameOverride,
                    contentType: contentType
                )
            }
        }

        return DraftMultipartPart(
            name: f.name,
            kind: .text,
            textValue: head,
            contentType: contentType
        )
    }

    /// Split `value;type=foo;filename=bar` while respecting `\;` escapes.
    private func splitFormValue(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\", s.index(after: i) < s.endIndex {
                let next = s[s.index(after: i)]
                if next == ";" {
                    current.append(";")
                    i = s.index(i, offsetBy: 2)
                    continue
                }
            }
            if c == ";" {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i = s.index(after: i)
        }
        parts.append(current)
        return parts
    }

    /// Concatenate body data from `-d/--data*` chunks. cURL semantics:
    /// - `--data` / `--data-ascii`: chunks joined with `&`; `@file` reads file (consent gated).
    /// - `--data-raw`: literal, joined with `&`; no `@file` semantics.
    /// - `--data-binary`: literal bytes; `@file` reads file as-is.
    /// - `--data-urlencode`: percent-encodes, joined with `&`.
    private func buildBody(chunks: [DataChunk],
                           userContentType: String?,
                           options: CurlImportOptions,
                           warnings: inout [String]) -> (Data, BodyEncoding, String?) {
        var pieces: [Data] = []

        for chunk in chunks {
            switch chunk.kind {
            case .data, .dataBinary:
                if chunk.value.hasPrefix("@") {
                    let path = String(chunk.value.dropFirst())
                    if path == "-" {
                        warnings.append("-d @-: stdin body is not supported; chunk skipped.")
                        continue
                    }
                    if options.loadLocalFiles {
                        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                            pieces.append(data)
                        } else {
                            warnings.append("Could not read \(path); chunk skipped.")
                        }
                    } else {
                        warnings.append(
                            "-d @\(path): local file reference requires consent; body left empty. " +
                            "Re-import with \"Load local files\" enabled to attach."
                        )
                    }
                } else {
                    pieces.append(Data(chunk.value.utf8))
                }

            case .dataRaw:
                pieces.append(Data(chunk.value.utf8))

            case .dataUrlEncoded:
                if chunk.value.hasPrefix("@") {
                    warnings.append("--data-urlencode @file is not supported; chunk skipped.")
                    continue
                }
                // cURL forms accepted by --data-urlencode:
                //   "content"        → percent-encoded(content)
                //   "=content"       → percent-encoded(content)
                //   "name=content"   → name + "=" + percent-encoded(content)
                //   "name@file"      → unsupported (warned)
                if let eq = chunk.value.firstIndex(of: "=") {
                    let name = String(chunk.value[..<eq])
                    let value = String(chunk.value[chunk.value.index(after: eq)...])
                    if name.isEmpty {
                        pieces.append(Data(urlencode(value).utf8))
                    } else {
                        pieces.append(Data("\(name)=\(urlencode(value))".utf8))
                    }
                } else {
                    pieces.append(Data(urlencode(chunk.value).utf8))
                }
            }
        }

        // -d joins chunks with `&` (cURL form-style).
        let joiner = Data("&".utf8)
        var combined = Data()
        for (i, p) in pieces.enumerated() {
            if i > 0 { combined.append(joiner) }
            combined.append(p)
        }

        // ── Encoding decision ────────────────────────────────────────────
        let ct = userContentType ?? defaultContentTypeFor(chunks: chunks)
        let encoding: BodyEncoding = {
            let lc = (ct ?? "").lowercased()
            if lc.contains("json") { return .json }
            if lc.contains("text") || lc.contains("xml") ||
               lc.contains("urlencoded") || lc.contains("javascript") {
                return .text
            }
            // Default: data chunks are textual unless we couldn't decode.
            if String(data: combined, encoding: .utf8) != nil { return .text }
            return .base64
        }()

        return (combined, encoding, userContentType == nil ? ct : nil)
    }

    private func defaultContentTypeFor(chunks: [DataChunk]) -> String? {
        guard !chunks.isEmpty else { return nil }
        // --data-binary preserves bytes verbatim; cURL doesn't add a default.
        if chunks.contains(where: { $0.kind == .dataBinary }) { return nil }
        return "application/x-www-form-urlencoded"
    }

    /// Per `--data-urlencode`: bare value → percent-encoded; `name=value` →
    /// `name=encoded(value)`; `=value` → `encoded(value)`.
    private func encodeDataChunksAsQuery(_ chunks: [DataChunk]) -> [DraftKeyValue] {
        var rows: [DraftKeyValue] = []
        for chunk in chunks {
            switch chunk.kind {
            case .dataUrlEncoded:
                rows.append(contentsOf: parseUrlencodeChunk(chunk.value))
            case .data, .dataRaw, .dataBinary:
                // -G with -d: the literal `name=value&...` is appended unchanged.
                for piece in chunk.value.split(separator: "&") {
                    let kv = piece.split(separator: "=", maxSplits: 1).map(String.init)
                    if kv.count == 2 {
                        rows.append(DraftKeyValue(key: kv[0],
                                                  value: percentDecode(kv[1])))
                    } else {
                        rows.append(DraftKeyValue(key: kv[0], value: ""))
                    }
                }
            }
        }
        return rows
    }

    private func parseUrlencodeChunk(_ s: String) -> [DraftKeyValue] {
        if s.hasPrefix("@") { return [] }   // file form unsupported, warned elsewhere
        if let eq = s.firstIndex(of: "=") {
            let name = String(s[..<eq])
            let value = String(s[s.index(after: eq)...])
            // The RHS is the *unencoded* user value; cURL urlencodes it itself.
            return [DraftKeyValue(key: name, value: value)]
        }
        return [DraftKeyValue(key: s, value: "")]
    }

    private func urlencode(_ s: String) -> String {
        // cURL encodes everything outside RFC 3986 unreserved.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func percentDecode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }
}

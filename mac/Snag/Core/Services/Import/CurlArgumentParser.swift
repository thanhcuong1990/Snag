import Foundation

enum DataChunkKind: Equatable {
    case data           // -d / --data / --data-ascii
    case dataRaw        // --data-raw
    case dataBinary     // --data-binary
    case dataUrlEncoded // --data-urlencode
}

struct DataChunk: Equatable {
    var kind: DataChunkKind
    var value: String
}

struct ParsedFormPart: Equatable {
    var name: String
    /// Raw RHS — may start with `@` for file refs and may contain
    /// `;type=…;filename=…` modifiers.
    var rawValue: String
    /// `--form-string` disables `@file` semantics.
    var allowFileRef: Bool
}

/// Intermediate representation after flag interpretation, before
/// projection onto `RequestDraftData`. Kept separate so the parser
/// stays unit-testable without touching draft persistence.
struct ParsedCurl: Equatable {
    var url: String?
    var method: String?
    var headers: [(String, String)] = []
    var dataChunks: [DataChunk] = []
    var formParts: [ParsedFormPart] = []
    var basicAuth: BasicAuth?
    var cookieValue: String?
    var followRedirects: Bool = false
    var locationTrusted: Bool = false
    var allowInsecure: Bool = false
    var maxTime: Double?
    var connectTimeout: Double?
    var compressed: Bool = false
    var getOverride: Bool = false
    var headOverride: Bool = false
    var warnings: [String] = []

    struct BasicAuth: Equatable {
        var user: String
        var password: String?
    }

    static func == (lhs: ParsedCurl, rhs: ParsedCurl) -> Bool {
        lhs.url == rhs.url &&
        lhs.method == rhs.method &&
        lhs.headers.elementsEqual(rhs.headers, by: { $0.0 == $1.0 && $0.1 == $1.1 }) &&
        lhs.dataChunks == rhs.dataChunks &&
        lhs.formParts == rhs.formParts &&
        lhs.basicAuth == rhs.basicAuth &&
        lhs.cookieValue == rhs.cookieValue &&
        lhs.followRedirects == rhs.followRedirects &&
        lhs.locationTrusted == rhs.locationTrusted &&
        lhs.allowInsecure == rhs.allowInsecure &&
        lhs.maxTime == rhs.maxTime &&
        lhs.connectTimeout == rhs.connectTimeout &&
        lhs.compressed == rhs.compressed &&
        lhs.getOverride == rhs.getOverride &&
        lhs.headOverride == rhs.headOverride &&
        lhs.warnings == rhs.warnings
    }
}

enum CurlArgumentParser {

    static func parse(_ tokens: [String]) -> ParsedCurl {
        var p = ParsedCurl()
        var i = 0

        if i < tokens.count, tokens[i].lowercased() == "curl" {
            i += 1
        }

        while i < tokens.count {
            let t = tokens[i]
            if t == "--" {
                // End-of-options sentinel; remaining tokens are positional.
                i += 1
                while i < tokens.count {
                    if p.url == nil { p.url = tokens[i] }
                    else { p.warnings.append("Ignored extra positional argument: \(tokens[i])") }
                    i += 1
                }
                break
            } else if t.hasPrefix("--") {
                i = consumeLongFlag(t, at: i, tokens: tokens, into: &p)
            } else if t.hasPrefix("-"), t.count > 1, t != "-" {
                i = consumeShortFlags(t, at: i, tokens: tokens, into: &p)
            } else {
                if p.url == nil {
                    p.url = t
                } else {
                    p.warnings.append("Ignored extra positional argument: \(t)")
                }
                i += 1
            }
        }

        return p
    }

    // MARK: - Long flags

    private static let longFlagsTakingValue: Set<String> = [
        "request", "header", "data", "data-raw", "data-binary",
        "data-urlencode", "data-ascii", "form", "form-string",
        "user", "cookie", "user-agent", "referer", "max-time",
        "connect-timeout", "url", "resolve", "connect-to",
        "cookie-jar", "request-target", "output", "proxy",
    ]

    private static func consumeLongFlag(_ token: String,
                                        at index: Int,
                                        tokens: [String],
                                        into p: inout ParsedCurl) -> Int {
        let body = String(token.dropFirst(2))
        let name: String
        let inline: String?
        if let eq = body.firstIndex(of: "=") {
            name = String(body[..<eq])
            inline = String(body[body.index(after: eq)...])
        } else {
            name = body
            inline = nil
        }

        var nextIndex = index + 1
        var value: String? = inline

        if longFlagsTakingValue.contains(name), value == nil {
            if nextIndex < tokens.count {
                value = tokens[nextIndex]
                nextIndex += 1
            } else {
                p.warnings.append("Flag --\(name) is missing a value.")
                return nextIndex
            }
        }

        applyLong(name: name, value: value, into: &p)
        return nextIndex
    }

    private static func applyLong(name: String, value: String?, into p: inout ParsedCurl) {
        switch name {
        case "request":
            p.method = value
        case "header":
            if let v = value, let h = splitHeader(v) { p.headers.append(h) }
        case "data", "data-ascii":
            if let v = value { p.dataChunks.append(DataChunk(kind: .data, value: v)) }
        case "data-raw":
            if let v = value { p.dataChunks.append(DataChunk(kind: .dataRaw, value: v)) }
        case "data-binary":
            if let v = value { p.dataChunks.append(DataChunk(kind: .dataBinary, value: v)) }
        case "data-urlencode":
            if let v = value { p.dataChunks.append(DataChunk(kind: .dataUrlEncoded, value: v)) }
        case "form":
            if let v = value, let f = parseFormPart(v, allowFileRef: true) { p.formParts.append(f) }
        case "form-string":
            if let v = value, let f = parseFormPart(v, allowFileRef: false) { p.formParts.append(f) }
        case "user":
            if let v = value { p.basicAuth = parseUserPass(v) }
        case "cookie":
            if let v = value { p.cookieValue = v }
        case "user-agent":
            if let v = value { p.headers.append(("User-Agent", v)) }
        case "referer":
            if let v = value { p.headers.append(("Referer", v)) }
        case "max-time":
            if let v = value, let d = Double(v) { p.maxTime = d }
        case "connect-timeout":
            if let v = value, let d = Double(v) {
                p.connectTimeout = d
                p.warnings.append("--connect-timeout=\(v): Snag uses a single timeout; recorded as a note.")
            }
        case "url":
            if p.url == nil { p.url = value }
        case "compressed":
            p.compressed = true
        case "get":
            p.getOverride = true
        case "insecure":
            p.allowInsecure = true
        case "location":
            p.followRedirects = true
        case "head":
            p.headOverride = true
        case "location-trusted":
            p.followRedirects = true
            p.locationTrusted = true
            p.warnings.append("--location-trusted: Snag follows URLSession's default credential-forwarding rules; behavior may differ.")
        case "resolve", "connect-to", "cookie-jar", "request-target", "proxy":
            if let v = value {
                p.warnings.append("--\(name)=\(v): preserved as a note; Snag does not apply it.")
            } else {
                p.warnings.append("--\(name): preserved as a note; Snag does not apply it.")
            }
        case "http1.0", "http1.1", "http2", "http2-prior-knowledge", "http3":
            p.warnings.append("--\(name): Snag uses URLSession's default protocol negotiation.")
        case "silent", "verbose", "show-error", "fail",
             "no-progress-meter", "progress-bar", "no-buffer",
             "globoff", "trace", "trace-ascii":
            break
        case "output":
            p.warnings.append("--output: ignored — Snag shows the response in the editor.")
        case "":
            // bare `--`, already handled by caller
            break
        default:
            p.warnings.append("Unknown flag --\(name): ignored.")
        }
    }

    // MARK: - Short flags (possibly stacked, e.g. `-kL` or `-Hfoo`)

    private static let shortFlagsTakingValue: Set<Character> = [
        "X", "H", "d", "F", "u", "b", "A", "e", "o", "x",
    ]

    private static func consumeShortFlags(_ token: String,
                                          at index: Int,
                                          tokens: [String],
                                          into p: inout ParsedCurl) -> Int {
        var nextIndex = index + 1
        let body = Array(token.dropFirst())
        var bi = 0

        while bi < body.count {
            let f = body[bi]

            if shortFlagsTakingValue.contains(f) {
                let rest = String(body[(bi + 1)...])
                let value: String
                if !rest.isEmpty {
                    value = rest
                    bi = body.count
                } else if nextIndex < tokens.count {
                    value = tokens[nextIndex]
                    nextIndex += 1
                    bi = body.count
                } else {
                    p.warnings.append("Flag -\(f) is missing a value.")
                    bi = body.count
                    continue
                }
                applyShort(flag: f, value: value, into: &p)
            } else {
                applyShort(flag: f, value: nil, into: &p)
                bi += 1
            }
        }
        return nextIndex
    }

    private static func applyShort(flag: Character, value: String?, into p: inout ParsedCurl) {
        switch flag {
        case "X":
            p.method = value
        case "H":
            if let v = value, let h = splitHeader(v) { p.headers.append(h) }
        case "d":
            if let v = value { p.dataChunks.append(DataChunk(kind: .data, value: v)) }
        case "F":
            if let v = value, let f = parseFormPart(v, allowFileRef: true) { p.formParts.append(f) }
        case "u":
            if let v = value { p.basicAuth = parseUserPass(v) }
        case "b":
            if let v = value { p.cookieValue = v }
        case "A":
            if let v = value { p.headers.append(("User-Agent", v)) }
        case "e":
            if let v = value { p.headers.append(("Referer", v)) }
        case "G":
            p.getOverride = true
        case "k":
            p.allowInsecure = true
        case "L":
            p.followRedirects = true
        case "I":
            p.headOverride = true
        case "s", "S", "v", "f", "#", "j", "n":
            break
        case "o":
            p.warnings.append("-o: ignored — Snag shows the response in the editor.")
        case "x":
            if let v = value {
                p.warnings.append("-x \(v): proxy is preserved as a note; Snag does not apply it.")
            }
        default:
            p.warnings.append("Unknown flag -\(flag): ignored.")
        }
    }

    // MARK: - Helpers

    private static func splitHeader(_ s: String) -> (String, String)? {
        // "Name: value" or "Name:value" — trim a single leading space after ':'.
        // "Name;" (header removal) is silently dropped.
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let rawName = s[..<colon]
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        var value = String(s[s.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        return (name, value)
    }

    private static func parseUserPass(_ s: String) -> ParsedCurl.BasicAuth {
        if let colon = s.firstIndex(of: ":") {
            return ParsedCurl.BasicAuth(
                user: String(s[..<colon]),
                password: String(s[s.index(after: colon)...])
            )
        }
        return ParsedCurl.BasicAuth(user: s, password: nil)
    }

    private static func parseFormPart(_ s: String, allowFileRef: Bool) -> ParsedFormPart? {
        guard let eq = s.firstIndex(of: "=") else { return nil }
        let name = String(s[..<eq])
        let value = String(s[s.index(after: eq)...])
        return ParsedFormPart(name: name, rawValue: value, allowFileRef: allowFileRef)
    }
}

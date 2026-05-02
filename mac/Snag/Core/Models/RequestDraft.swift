import Foundation
import Combine

enum BodyEncoding: String, Codable {
    case text
    case json
    case base64
    case multipart
}

enum DraftMultipartPartKind: String, Codable {
    case text
    case file
}

/// File parts are resolved at send time — the file is *not* copied into the draft, so
/// users can re-pick if it moves.
struct DraftMultipartPart: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var kind: DraftMultipartPartKind
    var textValue: String
    var fileURL: String?       // file:// URL string when kind == .file
    var fileName: String?      // override basename; nil → use URL.lastPathComponent
    var contentType: String?   // optional; auto-detected from extension when nil
    var enabled: Bool

    init(id: String = UUID().uuidString,
         name: String = "",
         kind: DraftMultipartPartKind = .text,
         textValue: String = "",
         fileURL: String? = nil,
         fileName: String? = nil,
         contentType: String? = nil,
         enabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.textValue = textValue
        self.fileURL = fileURL
        self.fileName = fileName
        self.contentType = contentType
        self.enabled = enabled
    }
}

struct DraftKeyValue: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var key: String
    var value: String
    var enabled: Bool

    init(id: String = UUID().uuidString, key: String = "", value: String = "", enabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.enabled = enabled
    }
}

struct DraftRun: Equatable {
    var startedAt: Date
    var finishedAt: Date?
    var statusCode: Int?
    var responseHeaders: [String: String]
    var responseBodyBase64: String?
    var responseBodyTruncated: Bool
    var durationMS: Double?
    var error: String?

    init(startedAt: Date = Date(),
         finishedAt: Date? = nil,
         statusCode: Int? = nil,
         responseHeaders: [String: String] = [:],
         responseBodyBase64: String? = nil,
         responseBodyTruncated: Bool = false,
         durationMS: Double? = nil,
         error: String? = nil) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBodyBase64 = responseBodyBase64
        self.responseBodyTruncated = responseBodyTruncated
        self.durationMS = durationMS
        self.error = error
    }
}

enum DraftValidationError: LocalizedError {
    case invalidURL
    case invalidScheme(String)
    case invalidHeader(String)
    case bodyTooLarge
    case multipartMissingFile(name: String)
    case multipartFileReadFailed(name: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL.".localized
        case .invalidScheme(let scheme):
            return "Unsupported URL scheme: \(scheme). Only http and https are allowed.".localized
        case .invalidHeader(let key):
            return "Header '\(key)' contains illegal characters (CR/LF).".localized
        case .bodyTooLarge:
            return "Request body exceeds the size limit.".localized
        case .multipartMissingFile(let name):
            return "Multipart part \"\(name)\" has no file selected.".localized
        case .multipartFileReadFailed(let name, let underlying):
            return "Multipart part \"\(name)\": \(underlying)".localized
        }
    }
}

/// Persisted, value-typed payload for a draft. Persisted as JSON.
struct RequestDraftData: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
    var method: String              // string-typed so unusual methods (PROPFIND etc.) round-trip
    var headers: [DraftKeyValue]
    var queryParams: [DraftKeyValue]
    var bodyBase64: String?
    var bodyEncoding: BodyEncoding
    var bodyContentType: String?
    var multipartParts: [DraftMultipartPart]
    var followRedirects: Bool
    var timeoutSeconds: Double
    var allowInvalidCertificates: Bool
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         name: String = "",
         url: String = "",
         method: String = "GET",
         headers: [DraftKeyValue] = [],
         queryParams: [DraftKeyValue] = [],
         bodyBase64: String? = nil,
         bodyEncoding: BodyEncoding = .text,
         bodyContentType: String? = nil,
         multipartParts: [DraftMultipartPart] = [],
         followRedirects: Bool = true,
         timeoutSeconds: Double = 30,
         allowInvalidCertificates: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.url = url
        self.method = method
        self.headers = headers
        self.queryParams = queryParams
        self.bodyBase64 = bodyBase64
        self.bodyEncoding = bodyEncoding
        self.bodyContentType = bodyContentType
        self.multipartParts = multipartParts
        self.followRedirects = followRedirects
        self.timeoutSeconds = timeoutSeconds
        self.allowInvalidCertificates = allowInvalidCertificates
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Custom decode tolerates older persisted JSON missing `multipartParts`.
    // Auto-synthesized Codable would fail on the missing key.
    private enum CodingKeys: String, CodingKey {
        case id, name, url, method, headers, queryParams,
             bodyBase64, bodyEncoding, bodyContentType, multipartParts,
             followRedirects, timeoutSeconds, allowInvalidCertificates,
             createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        method = try c.decode(String.self, forKey: .method)
        headers = try c.decode([DraftKeyValue].self, forKey: .headers)
        queryParams = try c.decode([DraftKeyValue].self, forKey: .queryParams)
        bodyBase64 = try c.decodeIfPresent(String.self, forKey: .bodyBase64)
        bodyEncoding = try c.decode(BodyEncoding.self, forKey: .bodyEncoding)
        bodyContentType = try c.decodeIfPresent(String.self, forKey: .bodyContentType)
        multipartParts = try c.decodeIfPresent([DraftMultipartPart].self, forKey: .multipartParts) ?? []
        followRedirects = try c.decode(Bool.self, forKey: .followRedirects)
        timeoutSeconds = try c.decode(Double.self, forKey: .timeoutSeconds)
        allowInvalidCertificates = try c.decode(Bool.self, forKey: .allowInvalidCertificates)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if let path = URL(string: url)?.path, !path.isEmpty { return "\(method) \(path)" }
        if !url.isEmpty { return "\(method) \(url)" }
        return "Untitled".localized
    }
}

/// Observable wrapper around `RequestDraftData`. UI binds to this; persistence reads `data`.
@MainActor
final class RequestDraft: ObservableObject, Identifiable {
    let id: String
    @Published var data: RequestDraftData
    /// Last execution result. Not persisted — re-running on relaunch is explicit.
    @Published var lastRun: DraftRun?
    /// Mirrors store snapshot; `true` while editor edits diverge from disk.
    @Published var isDirty: Bool = false

    init(data: RequestDraftData, lastRun: DraftRun? = nil) {
        self.id = data.id
        self.data = data
        self.lastRun = lastRun
    }
}

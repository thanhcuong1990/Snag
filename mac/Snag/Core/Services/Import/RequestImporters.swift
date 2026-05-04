import Foundation

/// Detected source kind for `ImportInput`. Drives the right parser dispatch.
enum DetectedFormat: Equatable {
    case singleCurl
    case multiCurl
    case postmanCollection
    case har
    case rawHTTP
    case unknown
}

/// Central auto-detect + dispatch for batch imports.
///
/// `parse(_:options:)` always returns an `ImportableBatch`. Single-cURL input
/// is wrapped in a one-row batch so the picker UI can stay uniform. Phase 3
/// only handles `singleCurl` and `multiCurl`; HAR/Postman flow through once
/// their importers ship in Phase 4.
enum RequestImporters {

    /// Inspect the input and return the most-likely format. Order matters —
    /// JSON checks happen first so a Postman or HAR JSON document doesn't get
    /// misread as a single cURL command.
    static func detect(_ input: ImportInput) -> DetectedFormat {
        let text: String
        do { text = try input.readText() }
        catch { return .unknown }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        if trimmed.first == "{" {
            // Cheap substring sniff. We do not parse the JSON here — the
            // importer parses it itself, and a malformed file becomes
            // .malformedJSON downstream.
            if trimmed.contains("\"info\""), trimmed.contains("\"item\"") {
                return .postmanCollection
            }
            if trimmed.contains("\"log\""), trimmed.contains("\"entries\"") {
                return .har
            }
            return .unknown
        }

        let count = MultiCurlImporter.curlCommandCount(text)
        if count >= 2 { return .multiCurl }

        let lower = trimmed.lowercased()
        if lower == "curl" || lower.hasPrefix("curl ") ||
           lower.hasPrefix("curl\t") || lower.hasPrefix("curl\n") ||
           lower.hasPrefix("curl\\") {
            return .singleCurl
        }

        if RawHTTPImporter.canHandle(input) {
            return .rawHTTP
        }

        return .unknown
    }

    /// Parse `input` into a uniform `ImportableBatch`, regardless of the
    /// underlying source format. Single-cURL becomes a 1-row batch.
    static func parse(_ input: ImportInput,
                      options: CurlImportOptions = CurlImportOptions(),
                      forced: DetectedFormat? = nil) throws -> ImportableBatch {
        let kind = forced ?? detect(input)
        switch kind {
        case .singleCurl:
            return try parseSingleCurl(input, options: options)
        case .multiCurl:
            return try MultiCurlImporter.parse(input, options: options)
        case .postmanCollection:
            return try PostmanCollectionImporter.parse(input, options: options)
        case .har:
            return try HARImporter.parse(input, options: options)
        case .rawHTTP:
            return try RawHTTPImporter.parse(input, options: options)
        case .unknown:
            throw ImportError.unrecognizedFormat
        }
    }

    private static func parseSingleCurl(_ input: ImportInput,
                                        options: CurlImportOptions) throws -> ImportableBatch {
        let text = try input.readText()
        let result = try CurlImporter.parse(text, options: options)
        let request = ImportableRequest(
            name: "Request 1".localized,
            draftData: result.draft,
            warnings: result.warnings
        )
        return ImportableBatch(
            sourceLabel: input.label,
            requests: [request],
            folders: nil
        )
    }
}

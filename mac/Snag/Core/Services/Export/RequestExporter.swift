import Foundation

/// Conformance for exporters that serialize a single draft into a snippet
/// (cURL, HTTPie, fetch, axios, ...). Bulk-capable formats (HAR, Postman)
/// implement `BulkRequestExporter` instead.
protocol RequestExporter {
    static func export(_ draft: RequestDraftData) -> String
}

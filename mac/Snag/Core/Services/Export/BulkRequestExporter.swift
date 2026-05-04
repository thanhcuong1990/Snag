import Foundation

/// Conformance for exporters that can serialize a batch of drafts into a
/// single document (HAR, Postman). Per-format dispatch lives in
/// `RequestExporters.exportBulk`.
protocol BulkRequestExporter {
    static func export(_ drafts: [RequestDraftData]) -> String
}

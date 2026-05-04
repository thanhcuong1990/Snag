import Foundation

/// Central dispatch from `ExportFormat` to the matching exporter.
/// Each new exporter registers a single switch arm here.
enum RequestExporters {

    /// Render a single draft as the requested format. Bulk formats wrap the
    /// single draft in an array.
    static func export(_ draft: RequestDraftData, as format: ExportFormat) -> String {
        switch format {
        case .curl: return CurlExporter.export(draft)
        case .httpie: return HTTPieExporter.export(draft)
        case .rawHTTP: return RawHTTPExporter.export(draft)
        case .pythonRequests: return PythonRequestsExporter.export(draft)
        case .jsFetch: return JSFetchExporter.export(draft)
        case .jsAxios: return JSAxiosExporter.export(draft)
        case .nodeHttp: return NodeHTTPExporter.export(draft)
        case .powershell: return PowerShellExporter.export(draft)
        case .har: return HARExporter.export([draft])
        case .postmanCollection: return PostmanCollectionExporter.export([draft])
        }
    }

    /// Render a batch of drafts as a single document. Throws if the format
    /// can't serialize a batch (`format.supportsBulk == false`).
    static func exportBulk(_ drafts: [RequestDraftData], as format: ExportFormat) throws -> String {
        guard format.supportsBulk else {
            throw ExportError.formatDoesNotSupportBulk(format)
        }
        switch format {
        case .har:
            return HARExporter.export(drafts)
        case .postmanCollection:
            return PostmanCollectionExporter.export(drafts)
        default:
            throw ExportError.formatDoesNotSupportBulk(format)
        }
    }
}

enum ExportError: LocalizedError {
    case formatDoesNotSupportBulk(ExportFormat)

    var errorDescription: String? {
        switch self {
        case .formatDoesNotSupportBulk(let f):
            return "\(f.displayName) cannot export multiple requests in one file."
        }
    }
}

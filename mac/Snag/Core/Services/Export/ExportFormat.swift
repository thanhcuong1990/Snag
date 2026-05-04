import Foundation

/// Per-language / per-tool snippet format the Code tab can render.
enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case curl
    case httpie
    case rawHTTP
    case pythonRequests
    case jsFetch
    case jsAxios
    case nodeHttp
    case powershell
    case har
    case postmanCollection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .curl: return "cURL"
        case .httpie: return "HTTPie"
        case .rawHTTP: return "Raw HTTP"
        case .pythonRequests: return "Python — requests"
        case .jsFetch: return "JavaScript — fetch"
        case .jsAxios: return "JavaScript — axios"
        case .nodeHttp: return "Node — http"
        case .powershell: return "PowerShell"
        case .har: return "HAR"
        case .postmanCollection: return "Postman Collection"
        }
    }

    var fileExtension: String {
        switch self {
        case .curl: return "sh"
        case .httpie: return "sh"
        case .rawHTTP: return "http"
        case .pythonRequests: return "py"
        case .jsFetch, .jsAxios, .nodeHttp: return "js"
        case .powershell: return "ps1"
        case .har: return "har"
        case .postmanCollection: return "json"
        }
    }

    var supportsBulk: Bool {
        switch self {
        case .har, .postmanCollection: return true
        default: return false
        }
    }
}

import Cocoa

class OverviewRepresentation: ContentRepresentation  {

    @MainActor
    init(overviewString: String) {
        super.init()
        self.rawString = overviewString
    }

    @MainActor
    init(requestInfo: SnagRequestInfo?) {
        super.init()

        if let requestInfo = requestInfo {
            self.rawString = Self.generateOverviewText(requestInfo: requestInfo)
        }
    }
    
    nonisolated static func generateOverviewText(requestInfo: SnagRequestInfo) -> String {
        var overviewString = ""
        
        overviewString = overviewString + "Method: " + (requestInfo.requestMethod?.rawValue ?? "") + "\n"
        overviewString = overviewString + "URL: " + (requestInfo.url ?? "") + "\n"
        overviewString = overviewString + "Status: " + (requestInfo.statusCode ?? "") + "\n"
        
        if let start = requestInfo.startDate, let end = requestInfo.endDate {
            let duration = end.timeIntervalSince(start)
            overviewString = overviewString + String(format: "Duration: %.2fms\n", duration * 1000)
        }
        
        if let body = requestInfo.requestBody {
             overviewString = overviewString + "Request Size: \(formatBytes(body.base64DecodedSize))\n"
             
             // Show a small preview if it's not massive
             if body.count < 100_000, let data = body.base64Data, let preview = String(data: data, encoding: .utf8) {
                 overviewString = overviewString + "\nRequest Body Preview:\n"
                 let snippet = String(preview.prefix(500))
                 overviewString = overviewString + snippet + (preview.count > 500 ? "..." : "") + "\n"
             }
        }
        
        if let responseData = requestInfo.responseData {
             overviewString = overviewString + "Response Size: \(formatBytes(responseData.base64DecodedSize))\n"
             
             if responseData.count < 100_000, let data = responseData.base64Data, let preview = String(data: data, encoding: .utf8) {
                 overviewString = overviewString + "\nResponse Body Preview:\n"
                 let snippet = String(preview.prefix(500))
                 overviewString = overviewString + snippet + (preview.count > 500 ? "..." : "") + "\n"
             }
        }
        
        return overviewString
    }
    
    nonisolated static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

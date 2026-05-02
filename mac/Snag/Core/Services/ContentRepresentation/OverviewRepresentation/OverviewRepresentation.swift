import Cocoa

class OverviewRepresentation: ContentRepresentation  {

    nonisolated private static let durationFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.usesSignificantDigits = true
        f.maximumSignificantDigits = 3
        f.minimumSignificantDigits = 1
        return f
    }()

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
            let ms = end.timeIntervalSince(start) * 1000
            overviewString = overviewString + "Duration: " + formatDuration(ms) + "\n"
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
    
    nonisolated static func formatDuration(_ ms: Double) -> String {
        if ms < 0 { return "0 ms" }
        let (value, unit) = ms < 1000 ? (ms, "ms") : (ms / 1000, "s")
        let formatted = durationFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formatted) \(unit)"
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

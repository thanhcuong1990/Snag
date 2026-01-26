import Cocoa

class OverviewRepresentation: ContentRepresentation  {

    init(requestInfo: SnagRequestInfo?) {
        
        super.init()

        if let requestInfo = requestInfo {
            
            var overviewString = ""
            
            overviewString = overviewString + "Method: " + (requestInfo.requestMethod?.rawValue ?? "") + "\n"
            overviewString = overviewString + "URL: " + (requestInfo.url ?? "") + "\n"
            overviewString = overviewString + "Status: " + (requestInfo.statusCode ?? "") + "\n"
            
            if let start = requestInfo.startDate, let end = requestInfo.endDate {
                let duration = end.timeIntervalSince(start)
                overviewString = overviewString + String(format: "Duration: %.2fms\n", duration * 1000)
            }
            
            if let bodyData = requestInfo.requestBody?.base64Data {
                 overviewString = overviewString + "Request Size: \(formatBytes(bodyData.count))\n"
            }
            
            if let responseData = requestInfo.responseData?.base64Data {
                 overviewString = overviewString + "Response Size: \(formatBytes(responseData.count))\n"
            }
            
            if let requestURLString = requestInfo.url, let requestURL = URL(string: requestURLString) {
                
                let contentRawString = (ContentRepresentationParser.keyValueRepresentation(url: requestURL).rawString ?? "")
                
                if contentRawString.count > 0 {
                    
                    overviewString = overviewString + "\n"
                    overviewString = overviewString + "URL Parameters:\n"
                    overviewString = overviewString + contentRawString
                }
            }
            
            self.rawString = overviewString
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

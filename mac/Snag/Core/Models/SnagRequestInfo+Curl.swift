import Foundation

extension SnagRequestInfo {
    func toCurlCommand(pretty: Bool = false) -> String? {
        guard let urlString = self.url,
              let url = URL(string: urlString) else {
            return nil
        }
        
        var parts: [String] = []
        
        // Base command
        parts.append("curl")
        
        // Method
        let method = self.requestMethod?.rawValue ?? "GET"
        parts.append("-X \(method)")
        
        // Headers
        if let headers = self.requestHeaders {
            let sortedHeaders = headers.sorted(by: { $0.key < $1.key })
            for (key, value) in sortedHeaders {
                // Escape double quotes in header values
                let escapedKey = key.replacingOccurrences(of: "\"", with: "\\\"")
                let escapedValue = value.replacingOccurrences(of: "\"", with: "\\\"")
                parts.append("-H \"\(escapedKey): \(escapedValue)\"")
            }
        }
        
        // Body
        if let body = self.requestBody, !body.isEmpty {
            var displayBody = body
            
            // Try to decode Base64 if it looks like it's encoded
            if let decodedData = body.base64Data,
               let decodedString = String(data: decodedData, encoding: .utf8) {
                displayBody = decodedString
            }
            
            // Escape single quotes for shell safety
            // Strategy: -d 'data' and escape ' as '\''
            let escapedBody = displayBody.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("--data-raw '\(escapedBody)'")
        }
        
        // URL
        // Wrap URL in quotes to handle special characters
        parts.append("\"\(url.absoluteString)\"")
        
        if pretty {
            return parts.joined(separator: " \\\n\t")
        } else {
            return parts.joined(separator: " ")
        }
    }
}

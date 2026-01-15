import SwiftUI

struct DetailsTopBar: View {
    let packet: SnagPacket?
    @ObservedObject var languageManager = LanguageManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            // Method Badge
            Text(packet?.requestInfo?.requestMethod?.rawValue ?? "-")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color.primary.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
            
            // Status Badge
            if let status = packet?.requestInfo?.statusCode, !status.isEmpty, status != "---" {
                let statusCodeInt = Int(status) ?? 0
                let statusText = shortStatusText(for: statusCodeInt)
                let fullStatus = "\(status) \(statusText)"
                
                Text(fullStatus)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: status))
                    .cornerRadius(4)
            }

            // URL
            Text(packet?.requestInfo?.url ?? "")
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .foregroundColor(Color(nsColor: ThemeColor.labelColor))
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    private func statusColor(for code: String) -> Color {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalizedCode == "ERR" { return Color(red: 239/255, green: 68/255, blue: 68/255) } // Red
        if normalizedCode.hasPrefix("2") || normalizedCode == "200" { return Color(red: 34/255, green: 197/255, blue: 94/255) } // Green
        if normalizedCode.hasPrefix("3") { return Color(red: 245/255, green: 158/255, blue: 11/255) } // Orange/Yellow
        if normalizedCode.hasPrefix("4") || normalizedCode.hasPrefix("5") { return Color(red: 239/255, green: 68/255, blue: 68/255) } // Red
        return Color.secondary
    }

    private func shortStatusText(for code: Int) -> String {
        switch code {
        case 200: return "OK".localized
        case 201: return "Created".localized
        case 202: return "Accepted".localized
        case 204: return "No Content".localized
        case 301: return "Moved Permanently".localized
        case 302: return "Found".localized
        case 304: return "Not Modified".localized
        case 400: return "Bad Request".localized
        case 401: return "Unauthorized".localized
        case 403: return "Forbidden".localized
        case 404: return "Not Found".localized
        case 500: return "Internal Server Error".localized
        case 502: return "Bad Gateway".localized
        case 503: return "Service Unavailable".localized
        default: return HTTPURLResponse.localizedString(forStatusCode: code).capitalized
        }
    }
}

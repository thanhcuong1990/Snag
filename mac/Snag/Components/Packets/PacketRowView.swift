import SwiftUI

struct PacketRowView: View {
    @ObservedObject var packet: SnagPacket
    let isSelected: Bool
    let isAlternate: Bool
    
    // MARK: - Static Formatters
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    // MARK: - Computed Properties
    
    private var isLoading: Bool {
        let code = packet.requestInfo?.statusCode ?? ""
        return (code.isEmpty || code == "---") && packet.requestInfo?.endDate == nil
    }
    
    private var statusIcon: String {
        let code = packet.requestInfo?.statusCode ?? ""
        if isLoading { return "arrow.triangle.2.circlepath" }
        if code.isEmpty || code == "---" { return "circle" }
        if code == "ERR" { return "exclamationmark.triangle.fill" }
        if code.hasPrefix("2") || code == "200" { return "checkmark.circle.fill" }
        if code.hasPrefix("3") { return "arrow.right.circle.fill" }
        if code.hasPrefix("4") || code.hasPrefix("5") { return "exclamationmark.circle.fill" }
        return "circle.fill"
    }
    
    private var statusColor: Color {
        let code = packet.requestInfo?.statusCode ?? ""
        if isSelected { return .white }
        if isLoading { return .methodGet }
        if code.isEmpty || code == "---" { return .secondaryLabelColor }
        if code == "ERR" { return .statusRed }
        if code.hasPrefix("2") { return .statusGreen }
        if code.hasPrefix("3") { return .statusOrange }
        if code.hasPrefix("4") || code.hasPrefix("5") { return .statusRed }
        return .secondaryLabelColor
    }
    
    private var methodColor: Color {
        if isSelected { return .white }
        switch packet.requestInfo?.requestMethod {
        case .get?: return .methodGet
        case .post?: return .methodPost
        case .put?: return .methodPut
        case .patch?: return .methodPatch
        case .delete?: return .methodDelete
        default: return .secondaryLabelColor
        }
    }
    
    private var responseSize: String {
        formatSize(packet.requestInfo?.responseData)
    }
    
    private var requestSize: String {
        formatSize(packet.requestInfo?.requestBody)
    }
    
    private var timeString: String {
        guard let date = packet.requestInfo?.startDate else { return "" }
        return Self.timeFormatter.string(from: date)
    }

    // MARK: - Helpers
    
    private func formatDuration(from start: Date?, end: Date?, now: Date) -> String {
        if let start = start, let end = end {
            let ms = end.timeIntervalSince(start) * 1000
            return formatMS(ms)
        } else if let start = start {
            // Live counting
            let ms = now.timeIntervalSince(start) * 1000
            let str = formatMS(ms)
            // Ensure width stability if needed, or just return natural string
             return str
        }
        return ""
    }
    
    private func formatMS(_ ms: Double) -> String {
        if ms < 0 { return "0.0 ms" }
        if ms < 1 {
            return String(format: "%.2f ms", ms)
        } else if ms < 1000 {
            return String(format: "%.1f ms", ms)
        }
        return String(format: "%.2f s", ms / 1000)
    }
    
    private func formatSize(_ base64String: String?) -> String {
        guard let dataStr = base64String, let data = Data(base64Encoded: dataStr) else { return "-" }
        let count = Double(data.count)
        if count < 1024 { return "\(Int(count)) bytes" }
        if count < 1024 * 1024 { return String(format: "%.1f KB", count / 1024) }
        return String(format: "%.1f MB", count / (1024 * 1024))
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private var durationView: some View {
        if let start = packet.requestInfo?.startDate, let end = packet.requestInfo?.endDate {
            // Static view for finished packets
            Text(formatDuration(from: start, end: end, now: Date()))
        } else {
            // Live view for active packets
             TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(formatDuration(from: packet.requestInfo?.startDate, 
                                    end: nil, 
                                    now: context.date))
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status Icon & Code
            HStack(spacing: 6) {
                if isLoading {
                    TimelineView(.animation(minimumInterval: 1/60)) { context in
                        let rotation = (context.date.timeIntervalSinceReferenceDate * 360).remainder(dividingBy: 360)
                        Image(systemName: statusIcon)
                            .font(.system(size: 11))
                            .rotationEffect(.degrees(rotation))
                    }
                } else {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11))
                }
                
                Text(packet.requestInfo?.statusCode ?? "---")
                    .font(.system(size: 11, weight: .regular))
            }
            .padding(.leading, 8)
            .foregroundColor(statusColor)
            .frame(width: 75, alignment: .leading)
            
            // Method
            Text(packet.requestInfo?.requestMethod?.rawValue ?? "")
                .font(.system(size: 11, weight: .regular))
                .padding(.leading, 8)
                .foregroundColor(methodColor)
                .frame(width: 60, alignment: .leading)
            
            // URL
            Text(packet.requestInfo?.url ?? "")
                .font(.system(size: 11, weight: .medium))
                .padding(.leading, 8)
                .foregroundColor(isSelected ? .white : .urlTextColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Duration
            durationView
                .font(.system(size: 11).monospacedDigit())
                .padding(.leading, 8)
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondaryLabelColor)
                .frame(width: 70, alignment: .leading)
                .transaction { $0.animation = nil }
            
            // Req. Size
            Text(requestSize)
                .font(.system(size: 11).monospacedDigit())
                .padding(.leading, 8)
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondaryLabelColor)
                .frame(width: 70, alignment: .leading)
            
            // Size
            Text(responseSize)
                .font(.system(size: 11).monospacedDigit())
                .padding(.leading, 8)
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondaryLabelColor)
                .frame(width: 70, alignment: .leading)
            
            // Time
            Text(timeString)
                .font(.system(size: 11).monospacedDigit())
                .padding(.leading, 8)
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondaryLabelColor)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: ThemeColor.rowSelectedColor))
                } else if isAlternate {
                    Rectangle()
                        .fill(Color.packetListAlternateBackgroundColor)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
        )
    }
}

import SwiftUI

struct LogsView: View {
    @StateObject var viewModel: LogsViewModel
    
    private enum Constants {
        static let padding: CGFloat = 8
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack {
                TextField("Filter logs...", text: $viewModel.filterTerm)
                    .textFieldStyle(.roundedBorder)
                
                Button(action: {
                    viewModel.togglePause()
                }) {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                }
                .help(viewModel.isPaused ? "Resume Auto-scroll" : "Pause Output")
                
                Button(action: {
                    viewModel.clearLogs()
                }) {
                    Image(systemName: "trash")
                }
                .help("Clear Logs")
            }
            .padding(Constants.padding)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Log List
            List {
                ForEach(viewModel.items) { log in
                    LogRowView(log: log)
                }
            }
            .listStyle(PlainListStyle())
        }
    }
}

struct LogRowView: View {
    let log: SnagLog
    
    struct Constants {
        static let verticalPadding: CGFloat = 4
        static let horizontalPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 4
        static let timestampWidth: CGFloat = 70
        static let messageIndent: CGFloat = 78
        static let tagHorizontalPadding: CGFloat = 4
        static let tagVerticalPadding: CGFloat = 2
    }
    
    private var lowercasedLogLevel: String {
        log.level.lowercased()
    }
    
    var backgroundColor: Color {
        switch lowercasedLogLevel {
        case "error", "fault": return Color(nsColor: .systemRed).opacity(0.1)
        case "warn", "warning": return Color(nsColor: .systemYellow).opacity(0.2)
        default: return Color.clear
        }
    }
    
    var textColor: Color {
        switch lowercasedLogLevel {
        case "error", "fault": return Color(nsColor: .systemRed)
        case "warn", "warning": return Color(nsColor: .systemOrange)
        case "debug": return .gray
        default: return .primary
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // Timestamp
                Text(datetimeFormatter.string(from: log.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: Constants.timestampWidth, alignment: .leading)
                
                // Level Tag
                Text(log.level.uppercased())
                    .modifier(TagModifier(backgroundColor: textColor.opacity(0.1), foregroundColor: textColor))
                
                if let tag = log.tag {
                    Text(tag)
                        .modifier(TagModifier(backgroundColor: Color.secondary.opacity(0.1), foregroundColor: .secondary))
                }
                
                Spacer()
            }
            
            // Message content
            Text(log.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .padding(.leading, Constants.messageIndent)
        }
        .padding(.vertical, Constants.verticalPadding)
        .padding(.horizontal, Constants.horizontalPadding)
        .background(backgroundColor)
        .cornerRadius(Constants.cornerRadius)
    }
}

private struct TagModifier: ViewModifier {
    let backgroundColor: Color
    let foregroundColor: Color
    
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .padding(.horizontal, LogRowView.Constants.tagHorizontalPadding)
            .padding(.vertical, LogRowView.Constants.tagVerticalPadding)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(LogRowView.Constants.cornerRadius)
    }
}

private let datetimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

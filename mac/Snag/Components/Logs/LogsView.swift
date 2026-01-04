import SwiftUI

struct LogsView: View {
    @StateObject var viewModel: LogsViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack {
                TextField("Filter logs...", text: $viewModel.filterTerm)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
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
            .padding(8)
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
    
    var colorForLevel: Color {
        switch log.level.lowercased() {
        case "error", "fault": return .red
        case "warn", "warning": return .orange
        case "debug": return .gray
        default: return .primary
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with timestamp, level, tag
            HStack(alignment: .top, spacing: 8) {
                Text(datetimeFormatter.string(from: log.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                
                Text(log.level.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(colorForLevel)
                    .frame(width: 50, alignment: .leading)
                
                if let tag = log.tag {
                    Text("[\(tag)]")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Message content
                Text(log.message)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(colorForLevel)
                    .textSelection(.enabled)
                
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}

private let datetimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

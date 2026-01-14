import SwiftUI

struct LogsView: View {
    @StateObject var viewModel: LogsViewModel
    
    private enum Constants {
        static let padding: CGFloat = 8
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            GeometryReader { geo in
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        
                        ZStack(alignment: .trailing) {
                            TextField("Filter logs...".localized, text: $viewModel.filterTerm)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 11))
                                .padding(.trailing, 16)
                            
                            if !viewModel.filterTerm.isEmpty {
                                Button(action: {
                                    viewModel.filterTerm = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .frame(width: geo.size.width * 0.5, alignment: .leading)
                    
                    Divider().frame(height: 14)
                    
                    (Text("\(viewModel.items.count)")
                        .foregroundColor(.primary) +
                    Text(" records".localized)
                        .foregroundColor(.secondary))
                        .font(.system(size: 11))
                    
                    Divider().frame(height: 14)
                    
                    HStack(spacing: 2) {
                        logLevelButton(.all)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1, height: 14)
                            .padding(.horizontal, 4)
                        
                        logLevelButton(.error)
                        logLevelButton(.warning)
                        logLevelButton(.info)
                        logLevelButton(.debug)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.togglePause()
                    }) {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                    }
                    .help(viewModel.isPaused ? "Resume Auto-scroll".localized : "Pause Output".localized)
                    
                    Button(action: {
                        viewModel.clearLogs()
                    }) {
                        Image(systemName: "trash")
                    }
                    .help("Clear Logs".localized)
                }
                .padding(.horizontal, Constants.padding)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 32)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))
            
            // Tag Filter Bar
            if !viewModel.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.tags, id: \.self) { tag in
                            TagChip(tag: tag, isSelected: viewModel.selectedTag == tag) {
                                if viewModel.selectedTag == tag {
                                    viewModel.selectedTag = nil
                                } else {
                                    viewModel.selectedTag = tag
                                }
                            }
                            
                            // Add a visual separator after the primary "Defined" tags
                            if tag == "System" && viewModel.tags.count > 3 {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 1, height: 14)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(.horizontal, Constants.padding)
                    .padding(.bottom, Constants.padding)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
            
            Divider()
            
            // Log List
            ScrollViewReader { proxy in
                List {
                    ForEach(viewModel.items) { log in
                        LogRowView(log: log)
                            .id(log.id) // Ensure we can identify the row
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: viewModel.items) { items in
                    guard !viewModel.isPaused, let firstLog = items.first else { return }
                    withAnimation {
                        proxy.scrollTo(firstLog.id, anchor: .top)
                    }
                }
            }
        }
    }
    private func logLevelButton(_ level: LogsViewModel.LogFilterLevel) -> some View {
        let isSelected = viewModel.selectedLogLevel == level
        return Text(level.localizedName)
            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isSelected ? Color.secondary.opacity(0.15) : Color.clear)
            .cornerRadius(3)
            .foregroundColor(isSelected ? .primary : .secondary)
            .onTapGesture {
                viewModel.selectedLogLevel = level
            }
    }
}

struct LogRowView: View {
    let log: SnagLog
    @State private var isExpanded: Bool = false
    
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
    
    private var isMultiLine: Bool {
        let trimmed = log.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("\n") || trimmed.count > 200
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                
                if isMultiLine {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            
            // Message content
            Text(log.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : 1)
                .padding(.leading, Constants.messageIndent)
                .padding(.trailing, 16)
        }
        .padding(.vertical, Constants.verticalPadding)
        .padding(.horizontal, Constants.horizontalPadding)
        .background(backgroundColor)
        .cornerRadius(Constants.cornerRadius)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
        .onTapGesture {
            if isMultiLine {
                isExpanded.toggle()
            }
        }
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

struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Text(tag)
            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(isSelected ? 0.18 : 0.08))
            .cornerRadius(4)
            .foregroundColor(isSelected ? .primary : .secondary)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}


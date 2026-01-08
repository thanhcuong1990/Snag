import SwiftUI

struct DataDetailView: View {
    @ObservedObject var viewModel: DataViewModel
    @ObservedObject var languageManager = LanguageManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isRaw: Bool = false
    
    @State private var forceShowLargeText: Bool = false
    
    private let largeTextThreshold = 1024 * 1024 // 1MB
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            } else if let data = viewModel.dataRepresentation {
                if data.type == .image {
                    // Image display
                    ImageContentView(data: data.originalData)
                } else if data.type == .json && !isRaw {
                    let size = data.originalData?.count ?? 0
                    if size > 500 * 1024 { // 500KB threshold for pretty viewer
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text(String(format: "JSON is large (%@). Pretty tree-view is disabled for performance.".localized, formatBytes(size)))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Try Anyway".localized) {
                                    // Maybe add a force override later
                                }.buttonStyle(.link)
                                .font(.system(size: 11))
                                .hidden()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            
                            CodeTextView(text: data.rawString ?? "")
                        }
                    } else {
                        JSONWebView(jsonString: data.rawString ?? "")
                    }
                } else {
                    let text = data.rawString ?? ""
                    let size = text.data(using: .utf8)?.count ?? 0
                    
                    if size > largeTextThreshold && !forceShowLargeText {
                        VStack(spacing: 0) {
                            Spacer()
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)
                                .padding(.bottom, 8)
                            Text("Text is very large (\(formatBytes(size)))")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Rendering this may cause the app to slow down.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.bottom, 16)
                            
                            HStack(spacing: 12) {
                                Button("Copy to Clipboard") {
                                    viewModel.copyToClipboard()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("View Anyway") {
                                    forceShowLargeText = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Spacer()
                        }
                    } else {
                        CodeTextView(text: text)
                    }
                }
            } else {
                Spacer()
                Text("No Data".localized).foregroundColor(.secondary).font(.system(size: 11, weight: .regular))
                Spacer()
            }
            
            HStack(spacing: 8) {
                // Show image info for image type
                if viewModel.dataRepresentation?.type == .image, let imageData = viewModel.dataRepresentation?.originalData {
                    if let image = NSImage(data: imageData) {
                        Text("\(Int(image.size.width))×\(Int(image.size.height)) • \(formatBytes(imageData.count))")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if viewModel.dataRepresentation?.type == .json {
                    DetailActionButton(title: "Raw".localized, iconName: "text.quote.rtl", isSelected: isRaw) {
                        isRaw.toggle()
                    }
                }
                
                DetailActionButton(title: "Copy".localized, iconName: "doc.on.doc") {
                    viewModel.copyToClipboard()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: ThemeColor.contentBarColor))
        }
        .onAppear {
            viewModel.register()
            viewModel.didSelectPacket()
        }
    }
    
    @ViewBuilder
    private func largePayloadWarning(size: Int) -> some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.blue)
            Text(String(format: "JSON is large (%@). Pretty tree-view is disabled for performance.".localized, formatBytes(size)))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
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

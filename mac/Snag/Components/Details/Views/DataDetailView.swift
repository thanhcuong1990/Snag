import SwiftUI

struct DataDetailView: View {
    @ObservedObject var viewModel: DataViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isRaw: Bool = false
    
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
                                Text("JSON is large (\(formatBytes(size))). Pretty tree-view is disabled for performance.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Try Anyway") {
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
                    CodeTextView(text: data.rawString ?? "")
                }
            } else {
                Spacer()
                Text("No Data").foregroundColor(.secondary).font(.system(size: 11, weight: .regular))
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
                    DetailActionButton(title: "Raw", iconName: "text.quote.rtl", isSelected: isRaw) {
                        isRaw.toggle()
                    }
                }
                
                DetailActionButton(title: "Copy", iconName: "doc.on.doc") {
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

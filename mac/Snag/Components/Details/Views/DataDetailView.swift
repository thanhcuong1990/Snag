import SwiftUI

struct DataDetailView: View {
    @ObservedObject var viewModel: DataViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var dataRepresentation: DataRepresentation?
    @State private var isRaw: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let data = dataRepresentation {
                if data.type == .image {
                    // Image display
                    ImageContentView(data: data.originalData)
                } else if data.type == .json && !isRaw {
                    JSONWebView(jsonString: data.rawString ?? "")
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
                if dataRepresentation?.type == .image, let imageData = dataRepresentation?.originalData {
                    if let image = NSImage(data: imageData) {
                        Text("\(Int(image.size.width))×\(Int(image.size.height)) • \(formatBytes(imageData.count))")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if dataRepresentation?.type == .json {
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
            update()
            viewModel.onChange = { update() }
        }
    }
    
    private func update() {
        dataRepresentation = viewModel.dataRepresentation
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

import SwiftUI

struct CurlView: View {
    @StateObject private var viewModel = CurlViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            } else {
                if viewModel.isTruncated {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("cURL body is large. Truncated for performance.".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Show Full".localized) {
                            viewModel.toggleFullBody()
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                }
                
                CurlHighlightedTextView(text: viewModel.curlRepresentation?.rawString ?? "")
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
            }
            
            HStack(spacing: 8) {
                Spacer()
                DetailActionButton(title: "Copy".localized, iconName: "doc.on.doc") {
                    viewModel.copyCURLToClipboard()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: ThemeColor.contentBarColor))
        }
        .onAppear {
            viewModel.register()
            viewModel.update()
        }
    }
}

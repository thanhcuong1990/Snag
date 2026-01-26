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

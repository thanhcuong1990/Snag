import SwiftUI

struct OverviewView: View {
    let packet: SnagPacket?
    @ObservedObject var languageManager = LanguageManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isCurl: Bool = false
    @StateObject private var viewModel = OverviewViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            if isCurl {
                CurlHighlightedTextView(text: viewModel.curlRepresentation?.rawString ?? "")
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
            } else {
                CodeTextView(text: viewModel.overviewRepresentation?.rawString ?? "")
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
            }
            
            HStack(spacing: 8) {
                Spacer()
                DetailActionButton(title: isCurl ? "Details".localized : "cURL", iconName: "terminal", isSelected: isCurl) {
                    isCurl.toggle()
                }
                
                DetailActionButton(title: "Copy".localized, iconName: "doc.on.doc") {
                    if isCurl { viewModel.copyCURLToClipboard() } else { viewModel.copyTextToClipboard() }
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
}

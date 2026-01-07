import SwiftUI

struct KeyValueListView: View {
    @ObservedObject var viewModel: KeyValueViewModel
    @ObservedObject var languageManager = LanguageManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isRaw: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isRaw {
                CodeTextView(text: viewModel.keyValueRepresentation?.rawString ?? "")
            } else if viewModel.items.isEmpty {
                Spacer()
                Text("No Headers".localized).foregroundColor(.secondary)
                    .font(.system(size: 11, weight: .regular))
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.items, id: \.key) { item in
                            HStack(alignment: .top, spacing: 0) {
                                Text(item.key ?? "")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 150, alignment: .leading)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                
                                Text(item.value ?? "")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Divider()
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                DetailActionButton(title: "Raw".localized, iconName: "text.quote.rtl", isSelected: isRaw) {
                    isRaw.toggle()
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
}

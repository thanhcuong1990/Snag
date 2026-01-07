import SwiftUI

struct LanguageToggleView: View {
    @ObservedObject var languageManager = LanguageManager.shared
    @State private var isHovering = false
    
    var body: some View {
        Menu {
            Picker("Language", selection: $languageManager.currentLanguage) {
                ForEach(LanguageManager.Language.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                Text(languageManager.currentLanguage.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize()
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton) // Use borderless to avoid default button chrome
        .menuIndicator(.hidden)
        .fixedSize() // Ensure it fits the content
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Change Language")
    }
}

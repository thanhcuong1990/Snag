import SwiftUI

struct LanguageToggleView: View {
    @ObservedObject var languageManager = LanguageManager.shared
    @State private var isHovering = false
    
    var body: some View {
        Menu {
            ForEach(LanguageManager.Language.allCases) { language in
                Button(action: {
                    languageManager.currentLanguage = language
                }) {
                    HStack {
                        Text(language.displayName)
                        if languageManager.currentLanguage == language {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 12))
                Text(languageManager.currentLanguage.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovering ? Color.secondary.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .onHover { hovering in
            isHovering = hovering
        }
        .fixedSize()
    }
}

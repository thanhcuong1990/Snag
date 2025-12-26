import SwiftUI

struct DetailActionButton: View {
    let title: String
    let iconName: String
    var isSelected: Bool = false
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .regular))
                Text(title)
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundColor(isSelected ? Color(nsColor: ThemeColor.labelColor) : (isHovered ? Color(nsColor: ThemeColor.labelColor) : Color(nsColor: ThemeColor.secondaryLabelColor)))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
        .cornerRadius(3)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

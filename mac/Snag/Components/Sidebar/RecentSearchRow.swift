import SwiftUI

struct RecentSearchRow: View {
    let text: String
    let action: () -> Void
    let deleteAction: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(.secondaryLabelColor)
            
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.labelColor)
                .lineLimit(1)
            
            Spacer()
            
            if isHovering {
                Button(action: deleteAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondaryLabelColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(isHovering ? Color.secondaryLabelColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hover in
            isHovering = hover
        }
    }
}

import SwiftUI

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    // Proxyman-style orange accent color
    private static let accentOrange = Color(red: 232/255, green: 85/255, blue: 53/255)
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(isSelected ? Self.accentOrange : Color.gray)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

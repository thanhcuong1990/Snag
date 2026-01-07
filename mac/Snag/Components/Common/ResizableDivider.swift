import SwiftUI

struct ResizableDivider: View {
    @Binding var isDragging: Bool
    var orientation: Axis = .horizontal
    var color: Color = Color.gray.opacity(0.3)
    @State private var isHovering: Bool = false
    
    var body: some View {
        Rectangle()
            .fill(isDragging || isHovering ? Color.accentColor : color)
            .frame(width: orientation == .horizontal ? (isDragging || isHovering ? 4 : 1) : nil,
                   height: orientation == .vertical ? (isDragging || isHovering ? 4 : 1) : nil)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    if orientation == .horizontal {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
    }
}

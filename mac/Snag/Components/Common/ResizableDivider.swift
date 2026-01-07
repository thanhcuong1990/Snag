import SwiftUI

struct ResizableDivider: View {
    @Binding var isDragging: Bool
    var orientation: Axis = .horizontal
    var color: Color = Color.gray.opacity(0.3)
    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor : color)
            .frame(width: orientation == .horizontal ? 1 : nil,
                   height: orientation == .vertical ? 1 : nil)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
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

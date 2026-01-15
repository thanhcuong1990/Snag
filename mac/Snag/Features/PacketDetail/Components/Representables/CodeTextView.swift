import SwiftUI
import AppKit

struct CodeTextView: NSViewRepresentable {
    let text: String
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = ThemeColor.textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor()
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        
        // Skip update if string hasn't changed to avoid expensive layout re-calculation
        if textView.string != text {
            textView.string = text
            // Optimization for very large text
            textView.layoutManager?.allowsNonContiguousLayout = true
        }
        
        nsView.drawsBackground = true
        
        // Use the colorScheme to resolve colors
        if let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) {
            appearance.performAsCurrentDrawingAppearance {
                textView.textColor = ThemeColor.textColor
                nsView.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor()
            }
        }
    }
}

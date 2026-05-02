import SwiftUI
import AppKit

struct CodeTextView: NSViewRepresentable {
    let text: String
    @Environment(\.colorScheme) var colorScheme

    class Coordinator {
        var lastTextHash: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

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

        // Compare a single Int hash instead of an O(n) string equality check on
        // potentially very large response bodies.
        let newHash = text.hashValue
        if context.coordinator.lastTextHash != newHash {
            textView.string = text
            // Optimization for very large text
            textView.layoutManager?.allowsNonContiguousLayout = true
            context.coordinator.lastTextHash = newHash
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

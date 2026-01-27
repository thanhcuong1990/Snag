import SwiftUI
import AppKit

struct CurlHighlightedTextView: NSViewRepresentable {
    let text: String
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor()
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        
        if let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) {
            appearance.performAsCurrentDrawingAppearance {
                textView.textStorage?.setAttributedString(highlightedText(from: text, isDark: colorScheme == .dark))
                nsView.drawsBackground = true
                nsView.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor()
            }
        }
    }
    
    private func highlightedText(from content: String, isDark: Bool) -> NSAttributedString {
        
        let textColor = isDark ? NSColor.white : NSColor.black
        let keywordColor = isDark ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0) : NSColor.systemBlue // curl, -X, -H, -d
        let urlColor = isDark ? NSColor(red: 0.5, green: 0.9, blue: 0.5, alpha: 1.0) : NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        let stringColor = isDark ? NSColor(red: 0.9, green: 0.7, blue: 0.4, alpha: 1.0) : NSColor(red: 0.6, green: 0.3, blue: 0.0, alpha: 1.0) // quoted values
        let commentColor = isDark ? NSColor.gray : NSColor.lightGray // backslashes
        
        let attributedString = NSMutableAttributedString(string: content, attributes: [
            .foregroundColor: textColor,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ])
        
        // Safety check: skip complex highlighting for very large text to avoid UI freeze
        if content.count > 100 * 1024 { // 100KB threshold
            return attributedString
        }
        
        func applyRegex(_ pattern: String, color: NSColor, bold: Bool = false) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let range = NSRange(content.startIndex..., in: content)
            regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
                if let matchRange = match?.range {
                    attributedString.addAttribute(.foregroundColor, value: color, range: matchRange)
                    if bold {
                        attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), range: matchRange)
                    }
                }
            }
        }
        
        // Match curl command
        applyRegex("^curl\\b", color: keywordColor, bold: true)
        
        // Match options (-H, -X, -d, --data, etc.)
        applyRegex("-(H|X|d|u|A|e|k|L|s|I|v|b|c|o|f)\\b", color: keywordColor)
        applyRegex("--(header|request|data|user|user-agent|referer|insecure|location|silent|head|verbose|cookie|output|fail)\\b", color: keywordColor)
        
        // Match quoted strings
        applyRegex("'[^']*'", color: stringColor)
        applyRegex("\"[^\"]*\"", color: stringColor)
        
        // Match URLs (starting with http/https)
        applyRegex("https?://[\\w.\\-/\\?&%=~_:#@\\[\\]!$*+,;]+", color: urlColor)
        
        // Match backslashes
        applyRegex("\\\\", color: commentColor)
        
        return attributedString
    }
}

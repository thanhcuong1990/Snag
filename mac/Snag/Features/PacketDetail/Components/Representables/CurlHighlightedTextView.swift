import SwiftUI
import AppKit

struct CurlHighlightedTextView: NSViewRepresentable {
    let text: String
    @Environment(\.colorScheme) var colorScheme

    private static let regularFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

    private static let curlRegex = try? NSRegularExpression(pattern: "^curl\\b", options: [])
    private static let shortOptionRegex = try? NSRegularExpression(pattern: "-(H|X|d|u|A|e|k|L|s|I|v|b|c|o|f)\\b", options: [])
    private static let longOptionRegex = try? NSRegularExpression(pattern: "--(header|request|data|user|user-agent|referer|insecure|location|silent|head|verbose|cookie|output|fail)\\b", options: [])
    private static let singleQuoteRegex = try? NSRegularExpression(pattern: "'[^']*'", options: [])
    private static let doubleQuoteRegex = try? NSRegularExpression(pattern: "\"[^\"]*\"", options: [])
    private static let urlRegex = try? NSRegularExpression(pattern: "https?://[\\w.\\-/\\?&%=~_:#@\\[\\]!$*+,;]+", options: [])
    private static let backslashRegex = try? NSRegularExpression(pattern: "\\\\", options: [])

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = Self.regularFont
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

        let attributedString = NSMutableAttributedString(string: content, attributes: [
            .foregroundColor: textColor,
            .font: Self.regularFont
        ])

        // Safety check first — bail before any regex work for very large text.
        if content.count > 100 * 1024 { // 100KB threshold
            return attributedString
        }

        let keywordColor = isDark ? NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0) : NSColor.systemBlue // curl, -X, -H, -d
        let urlColor = isDark ? NSColor(red: 0.5, green: 0.9, blue: 0.5, alpha: 1.0) : NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        let stringColor = isDark ? NSColor(red: 0.9, green: 0.7, blue: 0.4, alpha: 1.0) : NSColor(red: 0.6, green: 0.3, blue: 0.0, alpha: 1.0) // quoted values
        let commentColor = isDark ? NSColor.gray : NSColor.lightGray // backslashes

        let range = NSRange(content.startIndex..., in: content)

        func apply(_ regex: NSRegularExpression?, color: NSColor, bold: Bool = false) {
            guard let regex = regex else { return }
            regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
                if let matchRange = match?.range {
                    attributedString.addAttribute(.foregroundColor, value: color, range: matchRange)
                    if bold {
                        attributedString.addAttribute(.font, value: Self.boldFont, range: matchRange)
                    }
                }
            }
        }

        apply(Self.curlRegex, color: keywordColor, bold: true)
        apply(Self.shortOptionRegex, color: keywordColor)
        apply(Self.longOptionRegex, color: keywordColor)
        apply(Self.singleQuoteRegex, color: stringColor)
        apply(Self.doubleQuoteRegex, color: stringColor)
        apply(Self.urlRegex, color: urlColor)
        apply(Self.backslashRegex, color: commentColor)

        return attributedString
    }
}

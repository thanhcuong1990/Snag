import SwiftUI
import AppKit

/// Editable monospaced text view used by the body editor. Optional JSON syntax
/// highlighting is applied when `highlightJSON == true`.
struct EditableCodeTextView: NSViewRepresentable {
    @Binding var text: String
    var highlightJSON: Bool = false
    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = Self.regularFont
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        // Belt-and-suspenders: clear *all* text-checking types so AppKit can't
        // re-enable smart quotes via system defaults or Edit > Substitutions.
        textView.enabledTextCheckingTypes = 0
        textView.usesFindPanel = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor()

        textView.string = text
        applyAttributes(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        // Only push the binding's text into the view if it's drifted — avoids
        // resetting cursor/selection on every keystroke.
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            applyAttributes(textView)
            let safeLocation = min(selected.location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        } else {
            applyAttributes(textView)
        }

        if let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) {
            appearance.performAsCurrentDrawingAppearance {
                nsView.backgroundColor = DetailsTheme.jsonViewerBackgroundNSColor()
            }
        }
    }

    private func applyAttributes(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        storage.beginEditing()
        storage.setAttributes([
            .foregroundColor: ThemeColor.textColor,
            .font: Self.regularFont
        ], range: full)
        if highlightJSON, textView.string.count <= 200 * 1024 {
            JSONSyntaxHighlighter.highlight(storage: storage,
                                            text: textView.string,
                                            isDark: colorScheme == .dark)
        }
        storage.endEditing()
    }

    private static let regularFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableCodeTextView
        init(_ parent: EditableCodeTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// Cheap regex-based JSON colourizer. Lossy on edge cases (escaped quotes inside
/// strings, etc.) but pleasant on typical request bodies and free of any external
/// dependency.
enum JSONSyntaxHighlighter {
    private static let stringRegex = try? NSRegularExpression(
        pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", options: []
    )
    private static let keyRegex = try? NSRegularExpression(
        pattern: "\"(?:[^\"\\\\]|\\\\.)*\"\\s*:", options: []
    )
    private static let numberRegex = try? NSRegularExpression(
        pattern: "(?<![A-Za-z_])-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?", options: []
    )
    private static let keywordRegex = try? NSRegularExpression(
        pattern: "\\b(true|false|null)\\b", options: []
    )

    static func highlight(storage: NSTextStorage, text: String, isDark: Bool) {
        let stringColor = isDark ? NSColor(red: 0.93, green: 0.74, blue: 0.49, alpha: 1.0)
                                 : NSColor(red: 0.62, green: 0.31, blue: 0.0, alpha: 1.0)
        let keyColor = isDark ? NSColor(red: 0.49, green: 0.78, blue: 1.0, alpha: 1.0)
                              : NSColor(red: 0.0, green: 0.43, blue: 0.78, alpha: 1.0)
        let numberColor = isDark ? NSColor(red: 0.65, green: 0.85, blue: 0.65, alpha: 1.0)
                                 : NSColor(red: 0.06, green: 0.45, blue: 0.0, alpha: 1.0)
        let keywordColor = isDark ? NSColor(red: 0.85, green: 0.55, blue: 0.95, alpha: 1.0)
                                  : NSColor(red: 0.51, green: 0.0, blue: 0.65, alpha: 1.0)

        let full = NSRange(location: 0, length: (text as NSString).length)

        func apply(_ regex: NSRegularExpression?, color: NSColor, lengthOffset: Int = 0) {
            guard let regex = regex else { return }
            regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard var range = match?.range else { return }
                if lengthOffset != 0 {
                    range.length = max(0, range.length + lengthOffset)
                }
                if range.length > 0 {
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }

        apply(stringRegex, color: stringColor)
        // Re-color keys (overrides string match for the substring that ends with `"`)
        apply(keyRegex, color: keyColor, lengthOffset: -1) // drop trailing colon
        apply(numberRegex, color: numberColor)
        apply(keywordRegex, color: keywordColor)
    }
}

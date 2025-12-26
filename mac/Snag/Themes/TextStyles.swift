import Cocoa

class TextStyles {
    
    static let codeAttributes = [NSAttributedString.Key.foregroundColor: ThemeColor.labelColor, NSAttributedString.Key.font: FontManager.codeFont(size: 11)]

    static func codeAttributedString(string: String) -> NSAttributedString {
        return NSAttributedString(string: string, attributes: codeAttributes)
    }

    static func addCodeAttributesToHTMLAttributedString(htmlAttributedString: NSMutableAttributedString) {
        htmlAttributedString.addAttributes(codeAttributes, range: NSRange(location: 0, length: htmlAttributedString.string.count))
    }
}

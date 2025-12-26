import Cocoa

class FontManager: NSObject {

    static func mainFont(size: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: size)
    }
    
    static func mainLightFont(size: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: .light)
    }
    
    static func mainBoldFont(size: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }
    
    static func mainMediumFont(size: CGFloat) -> NSFont {
        return NSFont.systemFont(ofSize: size, weight: .medium)
    }
    
    static func codeFont(size: CGFloat) -> NSFont {
        if #available(macOS 10.15, *) {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        } else {
            return NSFont.userFixedPitchFont(ofSize: size) ?? NSFont.systemFont(ofSize: size)
        }
    }
    
}

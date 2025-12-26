import Cocoa

class ContentBar: NSBox {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setThemeColor()
    }
    
    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        self.setThemeColor()
    }
    
    func setThemeColor() {
        self.fillColor = ThemeColor.contentBarColor
    }
}

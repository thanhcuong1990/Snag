import Cocoa

class BaseTableHeaderView: NSTableHeaderView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        self.layer?.borderWidth = 0
    }
    
}

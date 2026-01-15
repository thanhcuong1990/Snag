import Cocoa

class FlatTableRowView: NSTableRowView {

    override func draw(_ dirtyRect: NSRect) {
        
        super.draw(dirtyRect)

        if self.isSelected {
            
            ThemeColor.rowSelectedColor.setFill() 
            
        }else {
            
            NSColor.clear.setFill()
        }
        
        dirtyRect.fill()
        self.drawSeparator(in: dirtyRect)
    }
    
}

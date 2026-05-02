import Cocoa

class DataImageRepresentation: DataRepresentation {
    var image: NSImage?

    override init(data: Data) {

        super.init(data: data)
        self.type = .image
        self.image = NSImage(data: data)
    }
    
    override func copyToClipboard() {
        
        if let originalData = self.originalData {
            
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(originalData, forType: .png)
        }
    }
}

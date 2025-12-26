import Cocoa

class DataImageRepresentation: DataRepresentation {

    override init(data: Data) {
        
        super.init(data: data)
        self.type = .image
    }
    
    override func copyToClipboard() {
        
        if let originalData = self.originalData {
            
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(originalData, forType: .png)
        }
    }
}

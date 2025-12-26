import Cocoa

class DataTextRepresentation: DataRepresentation {
    
    override init(data: Data) {
        
        super.init(data: data)
        self.type = .text
    }
}

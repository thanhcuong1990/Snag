import Cocoa

class DataJSONRepresentation: DataRepresentation  {
    
    override init(data: Data) {
        
        super.init(data: data)        
        self.type = .json
    }
}

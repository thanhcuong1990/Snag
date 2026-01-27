import Cocoa

class DataBinaryRepresentation: DataRepresentation {
    
    var sizeLabel: String {
        guard let data = originalData else { return "0 B" }
        let bytes = data.count
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
    
    override init(data: Data) {
        super.init(data: data)
        self.type = .binary
    }
}

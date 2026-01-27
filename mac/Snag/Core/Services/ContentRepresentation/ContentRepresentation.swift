import Cocoa

@MainActor
protocol ContentRepresentable {

    var rawString: String? {get}
    var attributedString: NSMutableAttributedString? {get}
    
    func copyToClipboard()
}

@MainActor
class ContentRepresentation: ContentRepresentable {
    
    var rawString: String?
    var attributedString: NSMutableAttributedString?
    
    func copyToClipboard() {
        
        if let rawString = self.rawString {
            
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rawString, forType: .string)
        }
    }
}

@MainActor
class ContentRepresentationParser {
    
    static func dataRepresentation(data: Data) -> DataRepresentation? {
        
        return DataRepresentationParser.parse(data: data)
    }
    
    @MainActor
    static func dataRepresentationAsync(data: Data) async -> DataRepresentation? {
        return await DataRepresentationParser.parseAsync(data: data)
    }
    
    @MainActor
    static func keyValueRepresentation(dictionary: Dictionary<String,String>) -> KeyValueRepresentation {
        
        let keyValueRepresentation = KeyValueRepresentation(keyValues: dictionary.toKeyValueArray())
        
        return keyValueRepresentation
    }
    
    @MainActor
    static func keyValueRepresentation(url: URL) -> KeyValueRepresentation {
        
        let keyValueRepresentation = KeyValueRepresentation(keyValues: url.toKeyValueArray())
        
        return keyValueRepresentation
    }
    
    @MainActor
    static func overviewRepresentation(requestInfo: SnagRequestInfo) -> ContentRepresentation {
        
        let overviewRepresentation = OverviewRepresentation(requestInfo: requestInfo)
        
        return overviewRepresentation
    }
}

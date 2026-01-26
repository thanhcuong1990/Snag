import Cocoa

enum DataRepresentationType {
    
    case json
    case image
    case text
}

class DataRepresentation: ContentRepresentation {
    
    var originalData: Data?
    var type: DataRepresentationType!
    
    init(data: Data) {
        self.originalData = data
    }
}

class DataRepresentationParser {
    
    static func parse(data: Data) -> DataRepresentation? {
        
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) {
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted) {
                
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    
                    let jsonData = DataJSONRepresentation(data: data)
                    jsonData.rawString = jsonString.replacingOccurrences(of: "\\/", with: "/")
                    return jsonData
                }
            }
            
        }else if let image = NSImage(data: data) {
            
            let textAttachmentCell = NSTextAttachmentCell(imageCell: image)
            let textAttachment = NSTextAttachment()
            textAttachment.attachmentCell = textAttachmentCell
            
            let attributedString = NSMutableAttributedString(attachment: textAttachment)
            
            let imageData = DataImageRepresentation(data: data)
            imageData.attributedString = attributedString
            return imageData
            
        }else if let htmlString = NSMutableAttributedString(html: data, documentAttributes: nil) {

            
            let textData = DataTextRepresentation(data: data)
            textData.rawString = htmlString.string
            textData.attributedString = htmlString
            return textData
            
        }else if let dataString = String(data: data, encoding: .utf8) {
            
            let textData = DataTextRepresentation(data: data)
            textData.rawString = dataString
            return textData
        }
        
        return nil
    }

    @MainActor
    static func parseAsync(data: Data) async -> DataRepresentation? {
        // Move ALL parsing logic to a detached task to avoid blocking the main thread
        return await Task.detached(priority: .userInitiated) {
            // Check for JSON first
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
               let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let str = String(data: jsonData, encoding: .utf8) {
                let representation = DataJSONRepresentation(data: data)
                representation.rawString = str.replacingOccurrences(of: "\\/", with: "/")
                representation.type = .json
                return representation
            }
            
            // Check for Images
            if let image = NSImage(data: data) {
                let textAttachmentCell = await NSTextAttachmentCell(imageCell: image)
                let textAttachment = NSTextAttachment()
                textAttachment.attachmentCell = textAttachmentCell
                
                let attributedString = NSMutableAttributedString(attachment: textAttachment)
                
                let imageData = DataImageRepresentation(data: data)
                imageData.attributedString = attributedString
                imageData.type = .image
                return imageData
            }
            
            // Check for HTML/Rich Text - but only if it's not too large
            // Expensive for large binary data
            if data.count < 1024 * 1024,
               let htmlString = NSMutableAttributedString(html: data, documentAttributes: nil) {
                let textData = DataTextRepresentation(data: data)
                textData.rawString = htmlString.string
                textData.attributedString = htmlString
                textData.type = .text
                return textData
            }
            
            // Plain Text fallback
            if let dataString = String(data: data, encoding: .utf8) {
                let textData = DataTextRepresentation(data: data)
                textData.rawString = dataString
                textData.type = .text
                return textData
            }
            
            return nil
        }.value
    }
}

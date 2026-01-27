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

@MainActor
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
        
        enum InternalResult {
            case json(String)
            case image(CGImage, NSSize)
            case text(String)
        }
        
        // Background Work
        let result: InternalResult? = await Task.detached(priority: .userInitiated) {
            // Check for JSON first
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
               let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let str = String(data: jsonData, encoding: .utf8) {
                return .json(str.replacingOccurrences(of: "\\/", with: "/"))
            }
            
            // Check for Images
            if let image = NSImage(data: data),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return .image(cgImage, image.size)
            }
            
            // Plain Text fallback
            if let dataString = String(data: data, encoding: .utf8) {
                return .text(dataString)
            }
            
            return nil
        }.value
        
        // Assemble on MainActor
        switch result {
        case .json(let str):
            let representation = DataJSONRepresentation(data: data)
            representation.rawString = str
            representation.type = .json
            return representation
            
        case .image(let cgImage, let size):
            let image = NSImage(cgImage: cgImage, size: size)
            let imageData = DataImageRepresentation(data: data)
            imageData.image = image
            imageData.type = .image
            
            let textAttachmentCell = NSTextAttachmentCell(imageCell: image)
            let textAttachment = NSTextAttachment()
            textAttachment.attachmentCell = textAttachmentCell
            imageData.attributedString = NSMutableAttributedString(attachment: textAttachment)
            
            return imageData
            
        case .text(let str):
            let textData = DataTextRepresentation(data: data)
            textData.rawString = str
            textData.type = .text
            return textData
            
        case .none:
            // Check for HTML if everything else failed
            if data.count < 1024 * 1024,
               let attributedString = NSMutableAttributedString(html: data, documentAttributes: nil) {
                let textData = DataTextRepresentation(data: data)
                textData.rawString = attributedString.string
                textData.attributedString = attributedString
                textData.type = .text
                return textData
            }
            return nil
        }
    }
}

import Cocoa

enum DataRepresentationType {
    
    case json
    case image
    case text
    case binary
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
    
    static func parse(data: Data, contentType: String? = nil) -> DataRepresentation? {
        
        // Hint-based optimization: check for images first if the content type suggests it
        if let contentType = contentType?.lowercased() {
            if contentType.contains("image/") {
                if let image = NSImage(data: data) {
                    let imageData = DataImageRepresentation(data: data)
                    imageData.image = image
                    
                    let textAttachmentCell = NSTextAttachmentCell(imageCell: image)
                    let textAttachment = NSTextAttachment()
                    textAttachment.attachmentCell = textAttachmentCell
                    imageData.attributedString = NSMutableAttributedString(attachment: textAttachment)
                    return imageData
                }
            } else if contentType.contains("multipart/") {
                // For now, if it's multipart, we try to find an image in it or return binary
                if let multipartResult = parseMultipart(data: data, contentType: contentType) {
                    return multipartResult
                }
            }
        }
        
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
            imageData.image = image
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
        
        // Fallback to binary for non-empty data
        if !data.isEmpty {
            return DataBinaryRepresentation(data: data)
        }
        
        return nil
    }

    @MainActor
    static func parseAsync(data: Data, contentType: String? = nil) async -> DataRepresentation? {
        
        enum InternalResult {
            case json(String)
            case image(CGImage, NSSize)
            case text(String)
            case binary
            case multipart(DataRepresentation)
        }
        
        // Background Work
        let result: InternalResult? = await Task.detached(priority: .userInitiated) {
            
            // Hint-based optimization
            if let ct = contentType?.lowercased() {
                if ct.contains("image/"), let image = NSImage(data: data),
                   let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    return .image(cgImage, image.size)
                }
                if ct.contains("multipart/"), let multi = await parseMultipart(data: data, contentType: ct) {
                    return .multipart(multi)
                }
            }
            
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
            
            // Plain Text fallback (only if it's reasonably sized and looks like text)
            if let dataString = String(data: data, encoding: .utf8) {
                // If it's very large and doesn't look like text, maybe it's binary
                if data.count > 1024 * 1024 && dataString.contains("\0") {
                    return .binary
                }
                return .text(dataString)
            }
            
            if !data.isEmpty {
                return .binary
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
            
        case .binary:
            return DataBinaryRepresentation(data: data)
            
        case .multipart(let repr):
            return repr
            
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
    
    private static func parseMultipart(data: Data, contentType: String) -> DataRepresentation? {
        // Find boundary
        guard let boundaryRange = contentType.range(of: "boundary="),
              let boundary = contentType[boundaryRange.upperBound...].split(separator: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else {
            return nil
        }
        
        let boundaryData = ("--" + boundary).data(using: .utf8)!
        
        // Simple search for the first part that looks like an image or data
        var currentOffset = 0
        while let range = data.range(of: boundaryData, options: [], in: currentOffset..<data.count) {
            let partStart = range.upperBound
            let nextRange = data.range(of: boundaryData, options: [], in: partStart..<data.count)
            let partEnd = nextRange?.lowerBound ?? data.count
            
            let partData = data.subdata(in: partStart..<partEnd)
            
            // Find where headers end (\r\n\r\n)
            if let headerEndRange = partData.range(of: Data([13, 10, 13, 10])) {
                let actualData = partData.subdata(in: headerEndRange.upperBound..<partData.count)
                
                // Try to see if this part is an image
                if let image = NSImage(data: actualData) {
                    let imageData = DataImageRepresentation(data: actualData)
                    imageData.image = image
                    imageData.type = .image
                    return imageData
                }
            }
            
            currentOffset = partEnd
            if nextRange == nil { break }
        }
        
        return nil
    }
}

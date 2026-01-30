import XCTest
import AppKit
@testable import Snag

class ImageNormalizationTests: XCTestCase {
    
    @MainActor
    func testImageNormalizationInParser() throws {
        // Create a simple 10x10 red image
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.set()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create test image data")
            return
        }
        
        // When parsing this data
        let representation = DataRepresentationParser.parse(data: pngData, contentType: "image/png")
        
        // Then it should be a DataImageRepresentation
        let imageRepr = try XCTUnwrap(representation as? DataImageRepresentation)
        let parsedImage = try XCTUnwrap(imageRepr.image)
        
        // And its size should match the pixel dimensions (10x10)
        XCTAssertEqual(parsedImage.size.width, 10)
        XCTAssertEqual(parsedImage.size.height, 10)
        
        // Verify CGImage dimensions as well
        if let cgImage = parsedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            XCTAssertEqual(CGFloat(cgImage.width), parsedImage.size.width)
            XCTAssertEqual(CGFloat(cgImage.height), parsedImage.size.height)
        }
    }
}

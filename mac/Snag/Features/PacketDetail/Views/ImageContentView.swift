import SwiftUI
import AppKit

struct ImageContentView: View {
    let data: Data?
    let image: NSImage?
    @Environment(\.colorScheme) var colorScheme
    
    init(data: Data? = nil, image: NSImage? = nil) {
        self.data = data
        self.image = image
    }
    
    var body: some View {
        let nsImage: NSImage? = {
            if let existing = image { return existing }
            guard let rawData = data, let newImage = NSImage(data: rawData) else { return nil }
            
            // Normalize image size to its pixel dimensions to fix high-DPI blurriness
            if let cgImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                newImage.size = NSSize(width: cgImage.width, height: cgImage.height)
            }
            return newImage
        }()
        
        if let imageToDisplay = nsImage {
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(nsImage: imageToDisplay)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                maxWidth: geometry.size.width - 16,
                                maxHeight: geometry.size.height - 16
                            )
                        Spacer()
                    }
                    Spacer()
                }
            }
            .padding(8)
            .background(DetailsTheme.backgroundColor)
        } else {
            VStack {
                Spacer()
                Image(systemName: "photo")
                    .font(.system(size: 40))
                Text("Unable to load image")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
}

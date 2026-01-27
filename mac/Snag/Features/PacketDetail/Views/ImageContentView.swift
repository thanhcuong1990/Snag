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
        if let nsImage = image ?? (data != nil ? NSImage(data: data!) : nil) {
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(nsImage: nsImage)
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

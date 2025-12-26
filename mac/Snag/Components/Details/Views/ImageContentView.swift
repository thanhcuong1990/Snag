import SwiftUI
import AppKit

struct ImageContentView: View {
    let data: Data?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if let data = data, let nsImage = NSImage(data: data) {
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

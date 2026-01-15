import SwiftUI

struct SidebarProjectHeader: View {
    @ObservedObject var project: SnagProjectController
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondaryLabelColor.opacity(0.1))
                    .frame(width: 28, height: 28)
                
                if let iconImage = iconImage {
                    Image(nsImage: iconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                } else {
                    Text(project.projectName?.prefix(1).uppercased() ?? "")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.labelColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text(project.projectName ?? "Unknown Project".localized)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.labelColor)
                
                Text(project.bundleId ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryLabelColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var iconImage: NSImage? {
        guard let appIcon = project.appIcon,
              let data = Data(base64Encoded: appIcon, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return NSImage(data: data)
    }
}

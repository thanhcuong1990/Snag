import SwiftUI

struct SidebarDeviceRow: View {
    @ObservedObject var device: SnagDeviceController
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Device Icon
            Image(systemName: deviceIconName(for: device.deviceDescription))
                .font(.system(size: 12, weight: .light))
                .frame(width: 16)
                .foregroundColor(isSelected ? .white : .secondaryLabelColor)
            
            Text(device.deviceName ?? "Unknown Device".localized)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .labelColor)
            
            Spacer()
            
            Text(deviceOSVersion(for: device.deviceDescription))
                .font(.system(size: 10))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondaryLabelColor.opacity(0.7))
                .padding(.trailing, 8)
        }
        .padding(.leading, 4) // Align icon with the App Icon in header (16 + 4 = 20)
        .padding(.trailing, 0) // Container has 16 padding, so 16 + 0 = 16
        .padding(.vertical, 6)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: ThemeColor.rowSelectedColor))
                }
            }
        )
        .contentShape(Rectangle())
    }
    
    private func deviceIconName(for description: String?) -> String {
        let desc = description?.lowercased() ?? ""
        if desc.contains("iphone") || desc.contains("ios") {
            return "iphone"
        } else if desc.contains("android") {
            return "smartphone"
        } else if desc.contains("mac") || desc.contains("macos") || desc.contains("x86_64") || desc.contains("arm64") {
            return "laptopcomputer"
        } else if desc.contains("ipad") {
            return "ipad"
        }
        return "desktopcomputer"
    }
    
    private func deviceOSVersion(for description: String?) -> String {
        let desc = description ?? ""
        if let range = desc.range(of: "\\d+(\\.\\d+)?", options: .regularExpression) {
            let version = String(desc[range])
            let lowerDesc = desc.lowercased()
            if lowerDesc.contains("ios") {
                return "iOS \(version)"
            } else if lowerDesc.contains("macos") {
                return "macOS \(version)"
            } else if lowerDesc.contains("android") {
                return "Android \(version)"
            }
            return version
        }
        return desc
    }
}

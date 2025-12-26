
import SwiftUI

struct SidebarView: View {
    @ObservedObject var snagController: SnagController = SnagController.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar Title/Header
            Text("REMOTE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondaryLabelColor)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if snagController.projectControllers.isEmpty {
                        EmptySidebarState()
                    } else {
                        ForEach(snagController.projectControllers, id: \.self) { project in
                            VStack(alignment: .leading, spacing: 12) {
                                SidebarProjectHeader(project: project)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(project.deviceControllers, id: \.self) { device in
                                        SidebarDeviceRow(
                                            device: device,
                                            isSelected: snagController.selectedProjectController == project && project.selectedDeviceController == device
                                        )
                                        .onTapGesture {
                                            snagController.selectedProjectController = project
                                            project.selectedDeviceController = device
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: ThemeColor.deviceListBackgroundColor))
    }
}

struct EmptySidebarState: View {
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 40)
            
            ZStack {
                Circle()
                    .stroke(Color.secondaryLabelColor.opacity(0.2), lineWidth: 1)
                    .frame(width: 50, height: 50)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 0 : 1)
                
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20))
                    .foregroundColor(.secondaryLabelColor.opacity(0.5))
            }
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
            
            VStack(spacing: 6) {
                Text("No Apps Connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondaryLabelColor)
                
                Text("Waiting for devices on port \(String(SnagConfiguration.netServicePort))...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryLabelColor.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SidebarProjectHeader: View {
    @ObservedObject var project: SnagProjectController
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondaryLabelColor.opacity(0.1))
                    .frame(width: 28, height: 28)
                
                Text(project.projectName?.prefix(1).uppercased() ?? "")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.labelColor)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text(project.projectName ?? "Unknown Project")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.labelColor)
                
                Text(projectBundleId(for: project.projectName))
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryLabelColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func projectBundleId(for projectName: String?) -> String {
        let name = projectName?.lowercased().replacingOccurrences(of: " ", with: ".") ?? "app"
        return "com.\(name).bundle"
    }
}

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
            
            Text(device.deviceName ?? "Unknown Device")
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

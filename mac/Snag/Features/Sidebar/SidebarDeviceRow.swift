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
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(device.deviceName ?? "Unknown Device".localized)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .labelColor)
                    
                    if !device.isAuthenticated {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondaryLabelColor)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 0) {
                Text(deviceOSVersion(for: device.deviceDescription))
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondaryLabelColor.opacity(0.7))
                
                if let ip = device.ipAddress {
                    Text(ip)
                        .font(.system(size: 9))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondaryLabelColor.opacity(0.6))
                        .padding(.top, 2)
                }
            }
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
        .onTapGesture {
            if device.isAuthenticated {
                selectDevice()
            } else {
                enteredPIN = ""
                errorMessage = nil
                shakeOffset = 0
                checkLockout() // Initial check
                showingPINPopover = true
            }
        }
        .popover(isPresented: $showingPINPopover, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter Security PIN".localized)
                    .font(.system(size: 12, weight: .bold))
                
                let lockout = lockoutRemaining()
                let isLocked = lockout != nil
                
                TextField("Security PIN".localized, text: Binding(
                    get: { enteredPIN },
                    set: { newValue in
                        errorMessage = nil
                        enteredPIN = newValue
                    }
                ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 160)
                    .disabled(isLocked)
                    .onSubmit {
                        performAuthorization()
                    }
                
                VStack(alignment: .leading, spacing: 0) {
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    } else if let remaining = lockout {
                        let minutes = remaining / 60
                        let seconds = remaining % 60
                        Text(String(format: "Device locked. Try again in %d:%02d".localized, minutes, seconds))
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    } else {
                        Text("Enter the PIN from your %@ device.".localized(with: deviceOSName(for: device.deviceDescription)))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 200, height: 30, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: false)
                
                HStack {
                    Spacer()
                    Button("Authorize".localized) {
                        performAuthorization()
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.small)
                    .disabled(enteredPIN.isEmpty || isLocked)
                }
            }
            .padding(16)
            .offset(x: shakeOffset)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                if showingPINPopover {
                    checkLockout()
                }
            }
        }
    }
    
    private func selectDevice() {
        // Find the project controller containing this device
        if let project = SnagController.shared.projectControllers.first(where: { $0.deviceControllers.contains(device) }) {
            SnagController.shared.selectedProjectController = project
            project.selectedDeviceController = device
        }
    }
    
    private func performAuthorization() {
        guard !enteredPIN.isEmpty else { return }
        
        // Check if device is locked out before attempting
        if let deviceId = device.deviceId {
            let lockoutStatus = SnagController.shared.isDeviceLocked(deviceId: deviceId)
            if lockoutStatus.locked, let remaining = lockoutStatus.remainingSeconds {
                let minutes = remaining / 60
                let seconds = remaining % 60
                errorMessage = String(format: "Device locked. Try again in %d:%02d".localized, minutes, seconds)
                return
            }
        }
        
        if SnagController.shared.authorizeDevice(device, enteredPIN: enteredPIN) {
            showingPINPopover = false
            errorMessage = nil
            selectDevice()
        } else {
            // Check if now locked out after this failed attempt
            if let deviceId = device.deviceId {
                let lockoutStatus = SnagController.shared.isDeviceLocked(deviceId: deviceId)
                if lockoutStatus.locked, let remaining = lockoutStatus.remainingSeconds {
                    let minutes = remaining / 60
                    let seconds = remaining % 60
                    errorMessage = String(format: "Too many attempts. Locked for %d:%02d".localized, minutes, seconds)
                } else {
                    errorMessage = "Incorrect PIN. Please try again.".localized
                }
            } else {
                errorMessage = "Incorrect PIN. Please try again.".localized
            }
            
            withAnimation(.default) {
                shakeOffset = 10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.default) {
                    shakeOffset = -10
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.default) {
                        shakeOffset = 0
                    }
                }
            }
        }
    }
    
    @State private var showingPINPopover = false
    @State private var enteredPIN = ""
    @State private var errorMessage: String? = nil
    @State private var shakeOffset: CGFloat = 0
    @State private var currentRemainingSeconds: Int? = nil
    
    private func checkLockout() {
        if let deviceId = device.deviceId {
            let status = SnagController.shared.isDeviceLocked(deviceId: deviceId)
            currentRemainingSeconds = status.remainingSeconds
        }
    }
    
    private func lockoutRemaining() -> Int? {
        return currentRemainingSeconds
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
    
    private func deviceOSName(for description: String?) -> String {
        let desc = description?.lowercased() ?? ""
        if desc.contains("iphone") || desc.contains("ios") || desc.contains("ipad") {
            return "iOS"
        } else if desc.contains("android") {
            return "Android"
        }
        return "device"
    }
}

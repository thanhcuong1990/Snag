import Foundation
#if canImport(UIKit)
import UIKit
#endif

class SnagUtility {
    static func uuid() -> String {
        return UUID().uuidString
    }
    
    static func projectName() -> String? {
        return Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ??
               Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String
    }
    
    static func bundleId() -> String? {
        return Bundle.main.bundleIdentifier
    }
    
    static func deviceId() -> String {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? uuid()
        #else
        let ip = ipAddress() ?? "unknown"
        return "\(self.hostName())-\(self.deviceName())-\(self.deviceDescription())-\(ip)"
        #endif
    }
    
    static func hostName() -> String {
        #if canImport(UIKit)
        // ProcessInfo.processInfo.hostName can trigger a blocking DNS lookup on iOS, 
        // leading to watchdog timeouts if called on the main thread during launch.
        // We use the device name as a safer alternative if available.
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }
    
    static func ipAddress() -> String? {
        var ipv4Address: String?
        var ipv6Address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                // Focus on common network interfaces (en0/en1 for WiFi/Ethernet, pdp_ip0 for Cellular)
                if name == "en0" || name == "en1" || name == "pdp_ip0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    let address = String(cString: hostname)
                    
                    if addrFamily == UInt8(AF_INET) {
                        // Prioritize WiFi (en0, en1) over cellular (pdp_ip0) for IPv4
                        if ipv4Address == nil || name.hasPrefix("en") {
                            ipv4Address = address
                        }
                    } else if ipv6Address == nil {
                        ipv6Address = address
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        
        // Prefer IPv4, fallback to IPv6
        return ipv4Address ?? ipv6Address
    }
    
    static func deviceName() -> String {
        #if canImport(UIKit)
        let explicitName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = UIDevice.current.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = self.deviceModelName() ?? model
        
        #if targetEnvironment(simulator)
        // For simulators, if the name is just "iPhone" or "iPad", return the descriptive model name
        if explicitName.caseInsensitiveCompare(model) == .orderedSame {
            return modelName
        }
        // If user has a specific name for the simulator, use it
        return explicitName
        #else
        // On real devices, if the user assigned a name (different from "iPhone"/"iPad"), use it.
        if explicitName.isEmpty || explicitName.caseInsensitiveCompare(model) == .orderedSame {
            return modelName
        }
        return explicitName
        #endif
        #else
        return Host.current().name ?? "Unknown Device"
        #endif
    }

    static func deviceModelName() -> String? {
        #if canImport(UIKit)
        let identifier = self.deviceModelIdentifier()
        guard let identifier, !identifier.isEmpty else { return nil }
        
        let map: [String: String] = [
            // iPhone 15
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            // iPhone 16
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            // iPhone 17 (Future/Projected)
            "iPhone18,1": "iPhone 17 Pro",
            "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17",
            "iPhone18,4": "iPhone 17 Plus"
        ]
        
        return map[identifier] ?? identifier
        #else
        return nil
        #endif
    }

    static func deviceModelIdentifier() -> String? {
        #if canImport(UIKit)
        if let simId = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simId.isEmpty {
            return simId
        }
        
        var systemInfo = utsname()
        uname(&systemInfo)
        
        let machine = withUnsafePointer(to: &systemInfo.machine) { ptr -> String in
            let int8Ptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            return String(cString: int8Ptr)
        }
        
        return machine
        #else
        return nil
        #endif
    }
    
    static func deviceDescription() -> String {
        #if canImport(UIKit)
        let information = "\(UIDevice.current.model) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        return information
        #else
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "macOS \(os)"
        #endif
    }
    
    static func appIcon() -> String? {
        #if canImport(UIKit)
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let lastIcon = iconFiles.last,
              let image = UIImage(named: lastIcon) else {
            return nil
        }
        return image.pngData()?.base64EncodedString()
        #else
        return nil
        #endif
    }
    
    static func securityPIN() -> String? {
        // 1. Check Launch Arguments (e.g. -SnagSecurityPIN 123456)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-SnagSecurityPIN"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        
        // 2. Check Environment Variables
        if let envPin = ProcessInfo.processInfo.environment["SnagSecurityPIN"] {
            return envPin
        }
        
        // 3. Check Info.plist
        return Bundle.main.object(forInfoDictionaryKey: "SnagSecurityPIN") as? String
    }
}

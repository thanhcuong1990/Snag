import Foundation
#if canImport(UIKit)
import UIKit
#endif

class SnagUtility {
    static func uuid() -> String {
        return UUID().uuidString
    }
    
    static func projectName() -> String? {
        return Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String
    }
    
    static func deviceId() -> String {
        return "\(self.deviceName())-\(self.deviceDescription())"
    }
    
    static func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().name ?? "Unknown Device"
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
}

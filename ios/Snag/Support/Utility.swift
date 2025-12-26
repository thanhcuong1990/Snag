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
}

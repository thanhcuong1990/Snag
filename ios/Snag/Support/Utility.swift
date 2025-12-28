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
        let explicitName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = UIDevice.current.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = self.deviceModelName() ?? model
        
        if explicitName.isEmpty {
            return modelName
        }
        
        if explicitName.caseInsensitiveCompare(model) == .orderedSame {
            return modelName
        }
        
        return explicitName
        #else
        return Host.current().name ?? "Unknown Device"
        #endif
    }

    static func deviceModelName() -> String? {
        #if canImport(UIKit)
        let identifier = self.deviceModelIdentifier()
        guard let identifier, !identifier.isEmpty else { return nil }
        
        let map: [String: String] = [
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max"
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
}

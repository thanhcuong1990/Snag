import Cocoa

class SnagConfiguration: NSObject {

    static let netServiceDomain: String = ""
    static let netServiceType: String = "_Snag._tcp"
    static let netServiceName: String = ""
    static let netServicePort: Int32 = 43435
    
    static var isSecurityEnabled: Bool = true
    static var forceInteractiveAuth: Bool {
        return SettingsManager.shared.forceInteractiveAuth
    }
    static var securityPIN: String? = String(format: "%06d", arc4random_uniform(1000000))
}

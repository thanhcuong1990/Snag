import Foundation

public class SnagConfiguration {
    public var project: SnagProject?
    public var device: SnagDevice?
    
    public weak var carrierDelegate: SnagCarrierDelegate?
    
    var netservicePort: UInt16 = 0
    var netserviceType: String?
    var netserviceDomain: String?
    var netserviceName: String?
    
    var deepLinkStarterURL: String?
    var publicKeyName: String?
    
    public var enableLogs: Bool = true
    public var isSecurityEnabled: Bool = true
    public var securityPIN: String?
    
    public static let defaultConfiguration: SnagConfiguration = {
        let config = SnagConfiguration()
        
        var project = SnagProject()
        project.name = SnagUtility.projectName()
        project.bundleId = SnagUtility.bundleId()
        // project.appIcon -> Defer to background
        
        var device = SnagDevice()
        device.id = SnagUtility.deviceId()
        device.name = SnagUtility.deviceName()
        device.description = SnagUtility.deviceDescription()
        device.hostName = SnagUtility.hostName()
        // device.ipAddress -> Defer to background
        
        config.project = project
        config.device = device
        
        config.netservicePort = 43435
        config.netserviceDomain = ""
        config.netserviceType = "_Snag._tcp"
        config.netserviceName = ""
        
        config.securityPIN = SnagUtility.securityPIN()
        
        return config
    }()
    
    public init() {
        self.project = SnagProject()
        self.device = SnagDevice()
    }
}

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
    
    public static let defaultConfiguration: SnagConfiguration = {
        let config = SnagConfiguration()
        
        var project = SnagProject()
        project.name = SnagUtility.projectName()
        project.appIcon = SnagUtility.appIcon()
        
        var device = SnagDevice()
        device.id = SnagUtility.deviceId()
        device.name = SnagUtility.deviceName()
        device.description = SnagUtility.deviceDescription()
        
        config.project = project
        config.device = device
        
        config.netservicePort = 43435
        config.netserviceDomain = ""
        config.netserviceType = "_Snag._tcp"
        config.netserviceName = ""
        
        return config
    }()
    
    public init() {
        self.project = SnagProject()
        self.device = SnagDevice()
    }
}

import Foundation

public class Snag {

    static var controller: SnagController?
    
    public static func start() {
        start(configuration: SnagConfiguration.defaultConfiguration)
    }
    
    public static func start(configuration: SnagConfiguration) {
        controller = SnagController(configuration: configuration)
        
        if configuration.enableLogs {
            if #available(iOS 15.0, *) {
                enableAutoLogCapture()
            }
        }
    }
    
    public static func log(_ message: String, level: String = "info", tag: String? = nil, details: [String: String]? = nil) {
        let log = SnagLog(level: level, message: message, tag: tag, details: details)
        controller?.send(log: log)
    }
    
    @available(iOS 15.0, *)
    public static func enableAutoLogCapture() {
        LogInterceptor.shared.startCapturing()
    }
}

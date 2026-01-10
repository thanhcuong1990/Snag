import Foundation

@objc(Snag)
public class Snag: NSObject {

    static var controller: SnagController?
    
    @objc public static func start() {
        start(configuration: SnagConfiguration.defaultConfiguration)
    }
    
    @objc public static func isEnabled() -> Bool {
        return controller != nil
    }
    
    public static func start(configuration: SnagConfiguration) {
        if controller != nil { return }
        controller = SnagController(configuration: configuration)
        
        if configuration.enableLogs {
            if #available(iOS 15.0, *) {
                enableAutoLogCapture()
            }
        }
    }
    
    @objc public static func log(_ message: String, level: String = "info", tag: String? = nil, details: [String: String]? = nil) {
        let log = SnagLog(level: level, message: message, tag: tag, details: details)
        controller?.send(log: log)
    }
    
    /// Simplified log for React Native zero-config hook
    @objc public static func logRN(_ message: String, level: String) {
        self.log(message, level: level, tag: "React Native")
    }
    
    @available(iOS 15.0, *)
    public static func enableAutoLogCapture() {
        Task {
            await LogInterceptor.shared.startCapturing()
        }
    }
}

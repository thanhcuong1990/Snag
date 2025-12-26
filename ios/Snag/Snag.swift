import Foundation

public class Snag {

    static var controller: SnagController?
    
    public static func start() {
        start(configuration: SnagConfiguration.defaultConfiguration)
    }
    
    public static func start(configuration: SnagConfiguration) {
        controller = SnagController(configuration: configuration)
    }
}

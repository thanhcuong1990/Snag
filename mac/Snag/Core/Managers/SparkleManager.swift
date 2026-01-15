import Foundation
import Sparkle

class SparkleManager: NSObject {
    static let shared = SparkleManager()
    
    let updaterController: SPUStandardUpdaterController
    
    private override init() {
        // SPUStandardUpdaterController is the recommended way to use Sparkle
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }
    
    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

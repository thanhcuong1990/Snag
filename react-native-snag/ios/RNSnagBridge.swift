import Foundation
import Snag

@objc public class RNSnagBridge: NSObject {
  @objc public static func start() {
    Snag.start()
  }

  @objc public static func log(_ message: String) {
    Snag.log(message)
  }
}

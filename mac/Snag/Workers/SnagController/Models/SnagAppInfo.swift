import Cocoa

struct SnagAppInfo: Codable {
    var bundleId: String?
    var isReactNative: Bool = false
}

import Cocoa

struct SnagAppInfo: Codable, Equatable {
    var bundleId: String?
    var isReactNative: Bool = false
}

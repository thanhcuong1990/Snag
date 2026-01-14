import Foundation

public struct SnagAppInfo: Codable, Sendable {
    public var bundleId: String?
    public var isReactNative: Bool = false
    
    public init(bundleId: String? = nil, isReactNative: Bool = false) {
        self.bundleId = bundleId
        self.isReactNative = isReactNative
    }
}

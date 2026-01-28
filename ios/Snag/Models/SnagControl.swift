import Foundation

public struct SnagControl: Codable, Sendable {
    public var type: String // "appInfoRequest", "appInfoResponse", "logStreamingControl", "logStreamingStatusRequest", "logStreamingStatusResponse"
    public var appInfo: SnagAppInfo?
    public var shouldStreamLogs: Bool?
    public var authPIN: String?
    
    public init(type: String, appInfo: SnagAppInfo? = nil, shouldStreamLogs: Bool? = nil, authPIN: String? = nil) {
        self.type = type
        self.appInfo = appInfo
        self.shouldStreamLogs = shouldStreamLogs
        self.authPIN = authPIN
    }
}

import Foundation

public struct SnagControl: Codable, Sendable {
    public var type: String
    
    // Handshake
    public var deviceId: String?
    public var authMode: String?
    public var encryptedPayload: Data?
    public var encryptedNonce: Data?
    
    public var appInfo: SnagAppInfo?
    public var shouldStreamLogs: Bool?
    
    public init(type: String, 
                appInfo: SnagAppInfo? = nil, 
                shouldStreamLogs: Bool? = nil, 
                deviceId: String? = nil,
                authMode: String? = nil,
                encryptedPayload: Data? = nil,
                encryptedNonce: Data? = nil) {
        self.type = type
        self.appInfo = appInfo
        self.shouldStreamLogs = shouldStreamLogs
        self.deviceId = deviceId
        self.authMode = authMode
        self.encryptedPayload = encryptedPayload
        self.encryptedNonce = encryptedNonce
    }
}

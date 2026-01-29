import Foundation

public struct SnagControl: Codable, Sendable {
    public var type: String
    
    // Handshake
    public var deviceId: String?
    public var salt: String?
    public var authHash: String?
    public var authMode: String?
    public var encryptedPayload: Data?
    public var encryptedNonce: Data?
    
    public var appInfo: SnagAppInfo?
    public var shouldStreamLogs: Bool?
    public var authPIN: String?
    
    public init(type: String, 
                appInfo: SnagAppInfo? = nil, 
                shouldStreamLogs: Bool? = nil, 
                authPIN: String? = nil,
                deviceId: String? = nil,
                salt: String? = nil,
                authHash: String? = nil,
                authMode: String? = nil,
                encryptedPayload: Data? = nil,
                encryptedNonce: Data? = nil) {
        self.type = type
        self.appInfo = appInfo
        self.shouldStreamLogs = shouldStreamLogs
        self.authPIN = authPIN
        self.deviceId = deviceId
        self.salt = salt
        self.authHash = authHash
        self.authMode = authMode
        self.encryptedPayload = encryptedPayload
        self.encryptedNonce = encryptedNonce
    }
}

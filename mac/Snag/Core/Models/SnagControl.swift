import Cocoa

struct SnagControl: Codable {
    var type: String // "hello", "auth_success", "data", "appInfoRequest", etc.
    
    // Handshake Fields
    var deviceId: String? // For "hello"
    var authMode: String? // "encrypted" or "cleartext" (For "auth_success")
    
    // Encrypted Data
    var encryptedPayload: Data?
    var encryptedNonce: Data?
    
    // Legacy / Other
    var appInfo: SnagAppInfo?
    var shouldStreamLogs: Bool?
}

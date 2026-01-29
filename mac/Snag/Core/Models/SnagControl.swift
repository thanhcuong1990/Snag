import Cocoa

struct SnagControl: Codable {
    var type: String // "hello", "auth_required", "auth_verify", "auth_success", "data", "appInfoRequest", etc.
    
    // Handshake Fields
    var deviceId: String? // For "hello"
    var salt: String? // For "auth_required" (Hex encoded)
    var authHash: String? // For "auth_verify" (Hex encoded)
    var authMode: String? // "encrypted" or "cleartext" (For "auth_success")
    
    // Encrypted Data
    var encryptedPayload: Data?
    var encryptedNonce: Data?
    
    // Legacy / Other
    var appInfo: SnagAppInfo?
    var shouldStreamLogs: Bool?
    var authPIN: String? // Deprecated: Was used for cleartext auth
}

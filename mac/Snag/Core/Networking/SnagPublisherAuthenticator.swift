import Foundation
import CryptoKit
import Network

class SnagPublisherAuthenticator {
    private let store: SnagPublisherStore
    
    // In-memory session state
    private var sessionKeys: [String: SymmetricKey] = [:] // DeviceID -> Session Key
    private var connectionSalts: [String: Data] = [:] // DeviceID -> Salt
    private var pendingAuthVerifications: [String: String] = [:] // DeviceID -> Client Hash
    
    private let maxFailedAttempts = 5
    private let lockoutDuration: TimeInterval = 300 // 5 minutes
    
    init(store: SnagPublisherStore) {
        self.store = store
    }
    
    func reset() {
        sessionKeys.removeAll()
        connectionSalts.removeAll()
        pendingAuthVerifications.removeAll()
    }
    
    // MARK: - Handshake Interaction
    
    func getSessionKey(for deviceId: String) -> SymmetricKey? {
        return sessionKeys[deviceId]
    }
    
    func hasSession(for deviceId: String) -> Bool {
        return sessionKeys[deviceId] != nil
    }
    
    func getSalt(for deviceId: String) -> Data? {
        return connectionSalts[deviceId]
    }
    
    func generateSalt(for deviceId: String) -> String {
        let salt = SnagCrypto.randomSalt()
        connectionSalts[deviceId] = salt
        return salt.map { String(format: "%02x", $0) }.joined()
    }
    
    func registerPendingVerification(deviceId: String, hash: String) {
        pendingAuthVerifications[deviceId] = hash
    }
    
    func getCachedPIN(for deviceId: String) -> String? {
        return store.knownPINs[deviceId]
    }
    
    // MARK: - Encryption
    
    func decrypt(packet: SnagPacket, deviceId: String) throws -> SnagPacket? {
        guard let key = sessionKeys[deviceId],
              let ciphertext = packet.control?.encryptedPayload,
              let nonce = packet.control?.encryptedNonce else {
            return nil
        }
        
        let plaintext = try SnagCrypto.decrypt(ciphertext: ciphertext, nonce: nonce, key: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(SnagPacket.self, from: plaintext)
    }
    
    // MARK: - Authorization Logic
    
    func authorizeDeviceLocked(deviceId: String, pin: String, onAuthenticated: (NWConnection) -> Void, sendPacket: (SnagPacket, NWConnection) -> Void, getConnection: (String) -> NWConnection?) -> Bool {
        // 1. Check Lockout
        if let lockoutExpiry = store.lockedOutDevices[deviceId] {
            if Date() < lockoutExpiry {
                print("Authenticator: Device \(deviceId) is locked out until \(lockoutExpiry)")
                return false
            } else {
                store.clearLockout(deviceId: deviceId)
            }
        }
        
        // 2. Validate IDs
        guard let connection = getConnection(deviceId),
              let salt = connectionSalts[deviceId],
              let clientHash = pendingAuthVerifications[deviceId] else {
            return false
        }
        
        // 3. Verify PIN
        let key = SnagCrypto.deriveKey(pin: pin, salt: salt)
        let validationString = "Client"
        var dataToHash = Data()
        key.withUnsafeBytes { dataToHash.append(contentsOf: $0) }
        dataToHash.append(Data(validationString.utf8))
        
        let computedHash = SHA256.hash(data: dataToHash).map { String(format: "%02x", $0) }.joined()
        
        if computedHash == clientHash {
            // SUCCESS
            sessionKeys[deviceId] = key
            store.authorizeDevice(deviceId: deviceId, pin: pin)
            onAuthenticated(connection)
            
            let successPacket = SnagPacket()
            successPacket.control = SnagControl(type: "auth_success", authMode: "encrypted")
            sendPacket(successPacket, connection)
            
            return true
        } else {
            // FAILURE
            store.recordFailedAttempt(deviceId: deviceId, maxFailedAttempts: maxFailedAttempts, lockoutDuration: lockoutDuration)
            return false
        }
    }
    
    func getLockoutStatus(deviceId: String) -> (locked: Bool, remainingSeconds: Int?) {
        if let lockoutExpiry = store.lockedOutDevices[deviceId] {
            let remaining = lockoutExpiry.timeIntervalSince(Date())
            if remaining > 0 {
                return (true, Int(remaining))
            }
        }
        return (false, nil)
    }
    
    func isAutoTrusted(connection: NWConnection, localIPs: [String]) -> Bool {
        if SnagConfiguration.forceInteractiveAuth { return false }
        guard let path = connection.currentPath else { return false }
        
        if path.usesInterfaceType(.loopback) || path.usesInterfaceType(.wiredEthernet) {
            return true
        }
        
        if case let .hostPort(host, _) = connection.endpoint {
            let hostStr = host.debugDescription
            if hostStr.contains("127.0.0.1") || hostStr.contains("::1") || hostStr.contains("localhost") {
                return true
            }
            for ip in localIPs {
                if hostStr.contains(ip) { return true }
            }
        }
        return false
    }
}

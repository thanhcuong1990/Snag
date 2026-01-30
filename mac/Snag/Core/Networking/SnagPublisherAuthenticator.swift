import Foundation
import CryptoKit
import Network

class SnagPublisherAuthenticator {
    private let store: SnagPublisherStore
    
    // In-memory session state
    private var sessionKeys: [String: SymmetricKey] = [:] // DeviceID -> Session Key
    private var connectionSalts: [ObjectIdentifier: Data] = [:] // Connection -> Salt
    private var pendingAuthVerifications: [ObjectIdentifier: String] = [:] // Connection -> Client Hash
    
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
        return sessionKeys[deviceId.lowercased()]
    }
    
    func hasSession(for deviceId: String) -> Bool {
        return sessionKeys[deviceId.lowercased()] != nil
    }
    
    func getSalt(for connection: NWConnection) -> Data? {
        return connectionSalts[ObjectIdentifier(connection)]
    }
    
    func generateSalt(for connection: NWConnection) -> String {
        let salt = SnagCrypto.randomSalt()
        connectionSalts[ObjectIdentifier(connection)] = salt
        return salt.map { String(format: "%02x", $0) }.joined()
    }
    
    func registerPendingVerification(connection: NWConnection, hash: String) {
        pendingAuthVerifications[ObjectIdentifier(connection)] = hash
    }
    
    func getCachedPIN(for deviceId: String) -> String? {
        return store.knownPINs[deviceId.lowercased()]
    }
    
    // MARK: - Encryption
    
    func decrypt(packet: SnagPacket, deviceId: String) throws -> SnagPacket? {
        guard let key = sessionKeys[deviceId.lowercased()],
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
    
    func authorizeDeviceLocked(connection: NWConnection, deviceId: String, pin: String, onAuthenticated: (NWConnection) -> Void, sendPacket: (SnagPacket, NWConnection) -> Void) -> Bool {
        let id = deviceId.lowercased()
        let connId = ObjectIdentifier(connection)
        
        // 1. Check Lockout
        if let lockoutExpiry = store.lockedOutDevices[id] {
            if Date() < lockoutExpiry {
                print("Authenticator: Device \(id) is locked out until \(lockoutExpiry)")
                return false
            } else {
                store.clearLockout(deviceId: id)
            }
        }
        
        // 2. Validate IDs
        guard let salt = connectionSalts[connId],
              let clientHash = pendingAuthVerifications[connId] else {
            print("Authenticator: Missing salt or verification for connection \(connId)")
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
            sessionKeys[id] = key
            store.authorizeDevice(deviceId: id, pin: pin)
            onAuthenticated(connection)
            
            let successPacket = SnagPacket()
            successPacket.control = SnagControl(type: "auth_success", deviceId: id, authMode: "encrypted")
            sendPacket(successPacket, connection)
            
            // Clean up handshake state
            connectionSalts.removeValue(forKey: connId)
            pendingAuthVerifications.removeValue(forKey: connId)
            
            return true
        } else {
            // FAILURE
            print("Authenticator: Hash mismatch for \(id). Expected \(computedHash), got \(clientHash)")
            store.recordFailedAttempt(deviceId: id, maxFailedAttempts: maxFailedAttempts, lockoutDuration: lockoutDuration)
            return false
        }
    }
    
    func getLockoutStatus(deviceId: String) -> (locked: Bool, remainingSeconds: Int?) {
        if let lockoutExpiry = store.lockedOutDevices[deviceId.lowercased()] {
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
        
        // 1. Loopback or Ethernet (usually trusted local physical network)
        if path.usesInterfaceType(.loopback) || path.usesInterfaceType(.wiredEthernet) {
            return true
        }
        
        // 2. Check Endpoint
        if case let .hostPort(host, _) = connection.endpoint {
            let hostStr = host.debugDescription
            
            // Standard loopback variations
            let loopbacks = ["127.0.0.1", "::1", "localhost"]
            if loopbacks.contains(where: { hostStr.contains($0) }) {
                return true
            }
            
            // Common Emulator Bridge Subnets (10.0.2.x, etc.)
            // On Mac, the connection might appear to come from a virtual interface IP.
            if hostStr.contains("10.0.") || hostStr.contains("192.168.56.") {
                return true
            }
            
            // Local IP check
            for ip in localIPs {
                // Exact match or contains for debugDescription which includes port
                if hostStr.contains(ip) { return true }
            }
        }
        return false
    }
}

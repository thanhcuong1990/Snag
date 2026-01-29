import Cocoa
import Network
import CryptoKit

protocol SnagPublisherDelegate {
    func didGetPacket(publisher: SnagPublisher, packet: SnagPacket)
}

class SnagPublisher: NSObject {

    var delegate: SnagPublisherDelegate?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var authenticatedConnections: Set<ObjectIdentifier> = []
    private var deviceConnections: [String: NWConnection] = [:]
    private var manuallyAuthorizedDeviceIds: Set<String> = []
    private var sessionKeys: [String: SymmetricKey] = [:] // DeviceID -> Session Key
    private var connectionSalts: [String: Data] = [:] // DeviceID -> Salt
    private var pendingAuthVerifications: [String: String] = [:] // DeviceID -> Client Hash
    private var knownPINs: [String: String] = [:] // DeviceID -> PIN (Session Cache)
    
    // Rate limiting for failed PIN attempts
    private var failedAuthAttempts: [String: Int] = [:] // DeviceID -> Count
    private var lockedOutDevices: [String: Date] = [:] // DeviceID -> Lockout Expiry
    private let maxFailedAttempts = 5
    private let lockoutDuration: TimeInterval = 300 // 5 minutes
    
    private let queue = DispatchQueue(label: "com.snag.publisher.queue")
    private let authorizedDevicesKey = "SnagAuthorizedDeviceIds"
    private let failedAttemptsKey = "SnagFailedAuthAttempts"
    private let lockedOutDevicesKey = "SnagLockedOutDevices"

    private lazy var jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private lazy var jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
    
    func startPublishing() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.loadAuthorizedDevices()
            self.loadLockoutState()
            self.stopPublishingLocked()
            do {
                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.enableKeepalive = true
                tcpOptions.noDelay = true

                let params: NWParameters
                if SnagConfiguration.isSecurityEnabled {
                    let tlsOptions = NWProtocolTLS.Options()
                    
                    sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
                    sec_protocol_options_set_max_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv13)
                    
                    if let identity = SnagIdentityManager.shared.getIdentity() {
                        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, identity)
                    } else {
                        print("SnagPublisher: ERROR - Failed to get TLS identity")
                    }
                    params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
                } else {
                    params = NWParameters(tls: nil, tcp: tcpOptions)
                }
                
                params.includePeerToPeer = true
                
                let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: UInt16(SnagConfiguration.netServicePort))!)
                
                listener.service = NWListener.Service(
                    name: SnagConfiguration.netServiceName.isEmpty ? nil : SnagConfiguration.netServiceName,
                    type: SnagConfiguration.netServiceType,
                    domain: SnagConfiguration.netServiceDomain.isEmpty ? nil : SnagConfiguration.netServiceDomain
                )
                
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        print("SnagPublisher: Ready and listening on port \(listener.port!)")
                        DispatchQueue.main.async {
                            SnagController.shared.publisherStatus = "Listening on \(listener.port!)"
                        }
                    case .failed(let error):
                        print("SnagPublisher: Listener failed with error: \(error)")
                        DispatchQueue.main.async {
                            SnagController.shared.publisherStatus = "Failed: \(error.localizedDescription)"
                        }
                        self.schedulePublishRetryLocked()
                    default:
                        break
                    }
                }
                
                listener.newConnectionHandler = { [weak self] connection in
                    self?.setupConnection(connection)
                }
                
                listener.start(queue: self.queue)
                self.listener = listener
                
            } catch {
                print("SnagPublisher: Failed to start listener: \(error)")
                self.schedulePublishRetryLocked()
            }
        }
    }

    private func setupConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.queue.async {
                switch state {
                case .ready:
                    let isTrusted = self.isAutoTrusted(connection: connection)
                    if isTrusted {
                        self.authenticatedConnections.insert(ObjectIdentifier(connection))
                    }
                    DispatchQueue.main.async {
                        SnagController.shared.publisherStatus = "Connected: \(connection.endpoint) (Trusted: \(isTrusted))"
                    }
                    self.receiveData(on: connection)
                case .failed(let error):
                    print("SnagPublisher: Connection failed: \(error)")
                    self.authenticatedConnections.remove(ObjectIdentifier(connection))
                    self.removeConnection(connection)
                    DispatchQueue.main.async {
                        SnagController.shared.publisherStatus = "Conn Failed: \(error.localizedDescription)"
                    }
                case .waiting(let error):
                    DispatchQueue.main.async {
                        SnagController.shared.publisherStatus = "Conn Waiting: \(error.localizedDescription)"
                    }
                case .cancelled:
                    self.authenticatedConnections.remove(ObjectIdentifier(connection))
                    self.removeConnection(connection)
                default:
                    break
                }
            }
        }
        
        queue.async {
            self.connections.append(connection)
            connection.start(queue: self.queue)
        }
    }

    private func receiveData(on connection: NWConnection) {
        // First, read the 8-byte length header
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let _ = error {
                connection.cancel()
                return
            }
            
            guard let data = data, data.count == 8 else {
                if isComplete { connection.cancel() }
                return
            }
            
            guard let length = self.lengthOf(data: data) else {
                connection.cancel()
                return
            }
            
            // Now read the body of specified length
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                
                self.queue.async {
                    if let _ = error {
                        self.removeConnection(connection)
                        self.authenticatedConnections.remove(ObjectIdentifier(connection))
                        connection.cancel()
                        return
                    }
                    
                    if let data = data {
                        self.processReceivedDataLocked(data, from: connection)
                    }
                    
                    // Continue reading next packet if not closed
                    if !isComplete {
                        self.receiveData(on: connection)
                    } else {
                        self.removeConnection(connection)
                        self.authenticatedConnections.remove(ObjectIdentifier(connection))
                        connection.cancel()
                    }
                }
            }
        }
    }

    private func isAutoTrusted(connection: NWConnection) -> Bool {
        if SnagConfiguration.forceInteractiveAuth { return false }
        
        guard let path = connection.currentPath else { return false }
        
        // Auto-trust loopback (Simulator)
        if path.usesInterfaceType(.loopback) { return true }
        
        // Auto-trust wired (USB)
        if path.usesInterfaceType(.wiredEthernet) { return true }

        // Additional check for Simulator/Localhost via IP
        if case let .hostPort(host, _) = connection.endpoint {
            let hostStr = host.debugDescription
            if hostStr.contains("127.0.0.1") || hostStr.contains("::1") || hostStr.contains("localhost") {
                return true
            }
            
            // Check if it's one of our own IP addresses (bonjour often gives LAN IP even for local simulator)
            let localIPs = self.getLocalIPAddresses()
            for ip in localIPs {
                if hostStr.contains(ip) {
                    return true
                }
            }
        }
        
        return false
    }

    private func getLocalIPAddresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface?.ifa_addr, socklen_t(interface?.ifa_addr.pointee.sa_len ?? 0),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    addresses.append(String(cString: hostname))
                }
            }
            freeifaddrs(ifaddr)
        }
        return addresses
    }

    private func removeConnection(_ connection: NWConnection) {
        queue.async {
            self.connections.removeAll { $0 === connection }
            self.deviceConnections = self.deviceConnections.filter { $0.value !== connection }
        }
    }

    private func stopPublishingLocked() {
        listener?.cancel()
        listener = nil
        
        connections.forEach { $0.cancel() }
        connections.removeAll()
        deviceConnections.removeAll()
        authenticatedConnections.removeAll()
        sessionKeys.removeAll()
        connectionSalts.removeAll()
        pendingAuthVerifications.removeAll()
    }
    
    private func lengthOf(data: Data) -> Int? {
        guard data.count >= 8 else { return nil }
        let length = data.withUnsafeBytes { $0.load(as: UInt64.self) }
        
        guard length > 0 && length <= 50_000_000 else {
            return nil
        }
        return Int(length)
    }

    private func processReceivedDataLocked(_ data: Data, from connection: NWConnection) {
        do {
            let snagPacket = try jsonDecoder.decode(SnagPacket.self, from: data)
            
            // 1. Handle Handshake Control Packets
            if let type = snagPacket.control?.type {
                print("SnagPublisher: Received control packet type '\(type)' from \(connection.endpoint)")
                if type == "hello" {
                    handleHello(packet: snagPacket, connection: connection)
                } else if type == "auth_verify" {
                    handleAuthVerify(packet: snagPacket, connection: connection)
                    return
                } else if type == "data" {
                    handleEncryptedData(packet: snagPacket, connection: connection)
                    return
                }
            } else {
                print("SnagPublisher: Received packet (no control) from \(connection.endpoint)")
            }
            
            // 2. Handle Cleartext / Auto-Trusted Packets
            // Only allow if connection is already trusted (Auto-Trust or previously authorized in cleartext mode, though we prefer encryption)
            let isTrusted = authenticatedConnections.contains(ObjectIdentifier(connection))
            
            // Allow discovery packets to bypass trust check so they appear in UI
            let isDiscovery = snagPacket.control?.type == "hello"
            
            // If security is enabled, we strictly require trust for any non-handshake packet.
            if SnagConfiguration.isSecurityEnabled && !isTrusted && !isDiscovery {
                print("SnagPublisher: Dropped unauthorized packet from \(connection.endpoint). Trusted: \(isTrusted), Discovery: \(isDiscovery)")
                return
            }
            
            if let deviceId = snagPacket.device?.deviceId {
                self.deviceConnections[deviceId] = connection
            }
            
            DispatchQueue.main.async {
                SnagController.shared.publisherStatus = "Packet from \(snagPacket.device?.deviceName ?? "Unknown")"
                self.delegate?.didGetPacket(publisher: self, packet: snagPacket)
            }
        } catch {
            DispatchQueue.main.async {
                SnagController.shared.publisherStatus = "Parse Error: \(error.localizedDescription)"
            }
        }
    }

    private func handleHello(packet: SnagPacket, connection: NWConnection) {
        // Register device ID mapping early if possible
        if let deviceId = packet.device?.deviceId {
            self.deviceConnections[deviceId] = connection
        }
        
        // Check if this device is already authenticated
        if let deviceId = packet.device?.deviceId {
            if self.sessionKeys[deviceId] != nil {
                // Device is already authenticated - auto-auth this new connection
                print("SnagPublisher: Device \(deviceId) already authenticated. Auto-authorizing new connection from \(connection.endpoint)")
                self.authenticatedConnections.insert(ObjectIdentifier(connection))
                
                // Send auth_success to this connection
                var successPacket = SnagPacket()
                successPacket.control = SnagControl(type: "auth_success", authMode: "encrypted")
                self.send(packet: successPacket, toConnection: connection)
                
                // Notify UI
                DispatchQueue.main.async {
                    self.delegate?.didGetPacket(publisher: self, packet: packet)
                }
                return
            }
            
            // If salt exists but not yet authenticated, re-send the same salt to new connection
            if let existingSalt = self.connectionSalts[deviceId] {
                print("SnagPublisher: Handshake pending for deviceId \(deviceId). Re-sending existing salt to new connection \(connection.endpoint)")
                let saltHex = existingSalt.map { String(format: "%02x", $0) }.joined()
                var challengePacket = SnagPacket()
                challengePacket.control = SnagControl(type: "auth_required", salt: saltHex)
                self.send(packet: challengePacket, toConnection: connection)
                return
            }
        }
        
        // check auto trust
        if isAutoTrusted(connection: connection) {
             print("SnagPublisher: Auto-trusting connection from \(connection.endpoint)")
             self.authenticatedConnections.insert(ObjectIdentifier(connection))
             
             // Send auth_success (cleartext) to client
             let successPacket = SnagPacket()
             successPacket.control = SnagControl(type: "auth_success", authMode: "cleartext")
             self.send(packet: successPacket, toConnection: connection)
             
             // Also notify local UI so the device is marked as authenticated immediately
             DispatchQueue.main.async {
                 // Forward the hello packet so device info is registered
                 self.delegate?.didGetPacket(publisher: self, packet: packet)
                 
                 // Also inject a local success packet to toggle isAuthenticated
                 var localSuccess = SnagPacket()
                 localSuccess.control = SnagControl(type: "auth_success")
                 localSuccess.device = packet.device
                 localSuccess.project = packet.project
                 self.delegate?.didGetPacket(publisher: self, packet: localSuccess)
             }
             return
        }
        
        // Start Handshake: Send Salt
        let salt = SnagCrypto.randomSalt()
        let saltHex = salt.map { String(format: "%02x", $0) }.joined()
        
        // Store salt by deviceId, not connection
        if let deviceId = packet.device?.deviceId {
            self.connectionSalts[deviceId] = salt
        } else {
            print("SnagPublisher: WARNING - No deviceId in hello packet, cannot store salt")
        }
        
        var challengePacket = SnagPacket()
        challengePacket.control = SnagControl(type: "auth_required", salt: saltHex)
        self.send(packet: challengePacket, toConnection: connection)
        
        DispatchQueue.main.async {
            SnagController.shared.publisherStatus = "Waiting for Auth: \(packet.device?.deviceName ?? "Unknown")"
        }
    }
    
    private func handleAuthVerify(packet: SnagPacket, connection: NWConnection) {
        guard let hash = packet.control?.authHash else { return }
        guard let deviceId = packet.device?.deviceId else {
            print("SnagPublisher: No deviceId in auth_verify packet")
            return
        }
        
        // Store by deviceId, not connection
        self.pendingAuthVerifications[deviceId] = hash
        
        // Auto-Auth Check: Do we have a cached PIN for this device?
        if let cachedId = self.knownPINs[deviceId] {
             print("SnagPublisher: Found cached PIN for \(deviceId). Attempting auto-auth.")
             if self.authorizeDevice(deviceId: deviceId, pin: cachedId) {
                 return // Success
             } else {
                 print("SnagPublisher: Cached PIN failed for \(deviceId). Removing from cache.")
                 self.knownPINs.removeValue(forKey: deviceId)
             }
        }
        
        // Now we wait for User to enter PIN via UI.
        // We trigger the UI by notifying the controller that this device exists (it's already in deviceConnections).
        // The UI should show "Locked" state.
        
        DispatchQueue.main.async {
             // Re-announce packet to ensure UI sees the device
             self.delegate?.didGetPacket(publisher: self, packet: packet)
        }
    }
    
    private func handleEncryptedData(packet: SnagPacket, connection: NWConnection) {
        // Get deviceId from the packet or look it up from the connection
        var deviceId: String? = packet.device?.deviceId
        
        // If no deviceId in packet, try to find it from connection mapping
        if deviceId == nil {
            for (id, conn) in self.deviceConnections where conn === connection {
                deviceId = id
                break
            }
        }
        
        guard let resolvedDeviceId = deviceId,
              let key = self.sessionKeys[resolvedDeviceId],
              let ciphertext = packet.control?.encryptedPayload,
              let nonce = packet.control?.encryptedNonce else {
            print("SnagPublisher: Missing key, ciphertext, or nonce for encrypted packet from \(connection.endpoint)")
            return
        }
        
        do {
            let plaintext = try SnagCrypto.decrypt(ciphertext: ciphertext, nonce: nonce, key: key)
            print("SnagPublisher: Decrypted \(plaintext.count) bytes from \(connection.endpoint)")
            
            do {
                let actualPacket = try jsonDecoder.decode(SnagPacket.self, from: plaintext)
                print("SnagPublisher: Decoded packet from \(connection.endpoint). ID: \(actualPacket.packetId ?? "nil")")
                
                // Process as normal
                DispatchQueue.main.async {
                    self.delegate?.didGetPacket(publisher: self, packet: actualPacket)
                }
            } catch {
                print("SnagPublisher: JSON Decoding failed for decrypted packet: \(error)")
                if let json = String(data: plaintext, encoding: .utf8) {
                    print("SnagPublisher: Malformed JSON: \(json)")
                }
            }
        } catch {
            print("SnagPublisher: Decryption failed for packet from \(connection.endpoint): \(error)")
        }
    }
    
    private func send(packet: SnagPacket, toConnection connection: NWConnection) {
        do {
            let framedData = try self.prepareFramedData(from: packet)
             connection.send(content: framedData, completion: .contentProcessed { error in
                 if let error = error {
                     print("SnagPublisher: Send error: \(error)")
                 }
             })
        } catch {
            print("SnagPublisher: Encode error: \(error)")
        }
    }

    private func prepareFramedData(from packet: SnagPacket) throws -> Data {
        let packetData = try jsonEncoder.encode(packet)
        var headerLength = UInt64(packetData.count)
        let headerData = Data(bytes: &headerLength, count: MemoryLayout<UInt64>.size)
        
        var buffer = Data(capacity: headerData.count + packetData.count)
        buffer.append(headerData)
        buffer.append(packetData)
        return buffer
    }

    private func send(data: Data, to connection: NWConnection, deviceId: String) {
        connection.send(content: data, completion: .contentProcessed { [weak connection] error in
            if let error = error {
                print("SnagPublisher: Send error to device \(deviceId): \(error)")
                connection?.cancel()
            }
        })
    }
    
    func send(packet: SnagPacket, toDeviceId deviceId: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let connection = self.deviceConnections[deviceId], connection.state == .ready else {
                print("SnagPublisher: No ready connection for device \(deviceId)")
                return
            }
            
            do {
                let framedData = try self.prepareFramedData(from: packet)
                self.send(data: framedData, to: connection, deviceId: deviceId)
            } catch {
                print("SnagPublisher: Encoding error for device \(deviceId): \(error)")
            }
        }
    }
    
    func broadcast(packet: SnagPacket) {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let framedData = try self.prepareFramedData(from: packet)
                for (deviceId, connection) in self.deviceConnections where connection.state == .ready {
                    self.send(data: framedData, to: connection, deviceId: deviceId)
                }
            } catch {
                print("SnagPublisher: Broadcast encoding error: \(error)")
            }
        }
    }
    
    func authorizeDevice(deviceId: String, pin: String) -> Bool {
        var success = false
        queue.sync { // Use sync to return result, ensure thread safety
             // Check if device is locked out
             if let lockoutExpiry = self.lockedOutDevices[deviceId] {
                 if Date() < lockoutExpiry {
                     print("SnagPublisher: Device \(deviceId) is locked out until \(lockoutExpiry)")
                     return
                 } else {
                     // Lockout expired, clear it
                     self.lockedOutDevices.removeValue(forKey: deviceId)
                     self.failedAuthAttempts.removeValue(forKey: deviceId)
                 }
             }
             
             guard let connection = self.deviceConnections[deviceId] else {
                 print("SnagPublisher: No connection found for deviceId \(deviceId)")
                 return
             }
             
             // Lookup by deviceId now (not connection)
             guard let salt = self.connectionSalts[deviceId] else {
                 print("SnagPublisher: No salt found for device \(deviceId)")
                 return
             }
             
             guard let clientHash = self.pendingAuthVerifications[deviceId] else {
                 print("SnagPublisher: No pending verify for device \(deviceId)")
                 return
             }
             
             // Verify
             let key = SnagCrypto.deriveKey(pin: pin, salt: salt)
             
             // The client sends: SHA256(KeyBytes + "Client".utf8)
             // We compute the same.
             let validationString = "Client"
             var dataToHash = Data()
             key.withUnsafeBytes { dataToHash.append(contentsOf: $0) }
             dataToHash.append(Data(validationString.utf8))
             
             let computedHash = SHA256.hash(data: dataToHash).map { String(format: "%02x", $0) }.joined()
             
             if computedHash == clientHash {
                 // Success - clear any failed attempts
                 self.failedAuthAttempts.removeValue(forKey: deviceId)
                 self.saveLockoutState()
                 
                 self.authenticatedConnections.insert(ObjectIdentifier(connection))
                 self.sessionKeys[deviceId] = key // Store by deviceId
                 self.manuallyAuthorizedDeviceIds.insert(deviceId)
                 self.knownPINs[deviceId] = pin // Cache PIN for re-auth
                 self.saveAuthorizedDevices()
                 
                // Send Success
                let successPacket = SnagPacket()
                successPacket.control = SnagControl(type: "auth_success", authMode: "encrypted")
                self.send(packet: successPacket, toConnection: connection)
                
                // Notify UI immediately (Simulate receiving an auth_success packet)
                let localSuccessPacket = SnagPacket()
                localSuccessPacket.control = SnagControl(type: "auth_success")
                let deviceModel = SnagDeviceModel()
                deviceModel.deviceId = deviceId
                localSuccessPacket.device = deviceModel
                
                DispatchQueue.main.async {
                    SnagController.shared.publisherStatus = String(format: "Authorized: %@".localized, deviceId)
                    self.delegate?.didGetPacket(publisher: self, packet: localSuccessPacket)
                }
                  
                print("SnagPublisher: Device \(deviceId) Authorized & Encrypted")
                success = true
            } else {
                // Increment failed attempts
                let attempts = (self.failedAuthAttempts[deviceId] ?? 0) + 1
                self.failedAuthAttempts[deviceId] = attempts
                
                if attempts >= self.maxFailedAttempts {
                    // Lock out the device
                    let lockoutExpiry = Date().addingTimeInterval(self.lockoutDuration)
                    self.lockedOutDevices[deviceId] = lockoutExpiry
                    print("SnagPublisher: Device \(deviceId) locked out for \(Int(self.lockoutDuration)) seconds after \(attempts) failed attempts")
                } else {
                    print("SnagPublisher: PIN Mismatch for \(deviceId). Failed attempt \(attempts)/\(self.maxFailedAttempts)")
                }
                self.saveLockoutState()
            }
        }
        return success
    }
    
    func getLockoutStatus(deviceId: String) -> (locked: Bool, remainingSeconds: Int?) {
        var result: (Bool, Int?) = (false, nil)
        queue.sync {
            if let lockoutExpiry = self.lockedOutDevices[deviceId] {
                let remaining = lockoutExpiry.timeIntervalSince(Date())
                if remaining > 0 {
                    result = (true, Int(remaining))
                }
            }
        }
        return result
    }

    func stopPublishing() {
        queue.async {
             self.stopPublishingLocked()
        }
    }

    private func loadAuthorizedDevices() {
        let saved = UserDefaults.standard.stringArray(forKey: authorizedDevicesKey) ?? []
        self.manuallyAuthorizedDeviceIds = Set(saved)
    }

    private func saveAuthorizedDevices() {
        UserDefaults.standard.set(Array(self.manuallyAuthorizedDeviceIds), forKey: authorizedDevicesKey)
    }
    
    private func saveLockoutState() {
        UserDefaults.standard.set(failedAuthAttempts, forKey: failedAttemptsKey)
        
        // Store Dates as time intervals for JSON-friendly persistence
        let lockedOutTimestamps = lockedOutDevices.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(lockedOutTimestamps, forKey: lockedOutDevicesKey)
    }

    private func loadLockoutState() {
        self.failedAuthAttempts = UserDefaults.standard.dictionary(forKey: failedAttemptsKey) as? [String: Int] ?? [:]
        
        if let savedTimestamps = UserDefaults.standard.dictionary(forKey: lockedOutDevicesKey) as? [String: Double] {
            self.lockedOutDevices = savedTimestamps.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }
    
    private var publishRetryScheduled = false
    private func schedulePublishRetryLocked() {
        if publishRetryScheduled { return }
        publishRetryScheduled = true
        queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.publishRetryScheduled = false
            self?.startPublishing()
        }
    }
}


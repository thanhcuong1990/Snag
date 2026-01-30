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
    
    private let store = SnagPublisherStore()
    private lazy var authenticator = SnagPublisherAuthenticator(store: store)
    
    private let queue = DispatchQueue(label: "com.snag.publisher.queue")
    
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
            self.store.loadAll()
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
                
                let port = NWEndpoint.Port(rawValue: UInt16(SnagConfiguration.netServicePort))!
                let listener = try NWListener(using: params, on: port)
                
                listener.service = NWListener.Service(
                    name: SnagConfiguration.netServiceName.isEmpty ? nil : SnagConfiguration.netServiceName,
                    type: SnagConfiguration.netServiceType,
                    domain: SnagConfiguration.netServiceDomain.isEmpty ? nil : SnagConfiguration.netServiceDomain
                )
                
                listener.stateUpdateHandler = { state in
                    DispatchQueue.main.async {
                        switch state {
                        case .ready:
                            SnagController.shared.publisherStatus = "Listening on \(listener.port!)"
                        case .failed(let error):
                            SnagController.shared.publisherStatus = "Failed: \(error.localizedDescription)"
                            self.schedulePublishRetryLocked()
                        default:
                            break
                        }
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
                    let isTrusted = self.authenticator.isAutoTrusted(connection: connection, localIPs: self.getLocalIPAddresses())
                    if isTrusted {
                        self.authenticatedConnections.insert(ObjectIdentifier(connection))
                    }
                    DispatchQueue.main.async {
                        SnagController.shared.publisherStatus = "Connected: \(connection.endpoint) (Trusted: \(isTrusted))"
                    }
                    self.receiveData(on: connection)
                case .failed(let error):
                    print("SnagPublisher: Connection failed: \(error)")
                    self.removeConnection(connection)
                case .cancelled:
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
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if error != nil {
                connection.cancel()
                return
            }
            
            guard let data = data, data.count == 8, let length = self.lengthOf(data: data) else {
                if isComplete { connection.cancel() }
                return
            }
            
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] bodyData, _, bodyIsComplete, bodyError in
                guard let self = self else { return }
                self.queue.async {
                    if bodyError != nil {
                        self.removeConnection(connection)
                        connection.cancel()
                        return
                    }
                    
                    if let bodyData = bodyData {
                        self.processReceivedDataLocked(bodyData, from: connection)
                    }
                    
                    if !bodyIsComplete { self.receiveData(on: connection) }
                    else {
                        self.removeConnection(connection)
                        connection.cancel()
                    }
                }
            }
        }
    }

    private func processReceivedDataLocked(_ data: Data, from connection: NWConnection) {
        do {
            let snagPacket = try jsonDecoder.decode(SnagPacket.self, from: data)
            let type = snagPacket.control?.type
            
            if type == "hello" {
                handleHello(packet: snagPacket, connection: connection)
            } else if type == "auth_verify" {
                handleAuthVerify(packet: snagPacket, connection: connection)
            } else if type == "data" {
                handleEncryptedData(packet: snagPacket, connection: connection)
            } else if let deviceId = (snagPacket.device?.deviceId ?? snagPacket.control?.deviceId)?.lowercased() {
                // Regular packet
                if isTrusted(connection: connection, packet: snagPacket) {
                    self.deviceConnections[deviceId] = connection
                    DispatchQueue.main.async {
                        SnagController.shared.publisherStatus = "Packet from \(snagPacket.device?.deviceName ?? "Unknown")"
                        self.delegate?.didGetPacket(publisher: self, packet: snagPacket)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { SnagController.shared.publisherStatus = "Parse Error" }
        }
    }
    
    private func isTrusted(connection: NWConnection, packet: SnagPacket) -> Bool {
        let isHandshake = packet.control?.type != nil && packet.control?.type != "data"
        if isHandshake { return true }
        
        let isTrusted = authenticatedConnections.contains(ObjectIdentifier(connection))
        if SnagConfiguration.isSecurityEnabled && !isTrusted {
            print("SnagPublisher: Dropped unauthorized packet from \(connection.endpoint)")
            return false
        }
        return true
    }

    private func handleHello(packet: SnagPacket, connection: NWConnection) {
        guard let deviceId = (packet.device?.deviceId ?? packet.control?.deviceId)?.lowercased() else { return }
        self.deviceConnections[deviceId] = connection
        
        // 1. Existing Session?
        if authenticator.hasSession(for: deviceId) {
            self.authenticatedConnections.insert(ObjectIdentifier(connection))
            let successPacket = SnagPacket()
            successPacket.control = SnagControl(type: "auth_success", authMode: "encrypted")
            self.send(packet: successPacket, toConnection: connection)
            DispatchQueue.main.async {
                self.delegate?.didGetPacket(publisher: self, packet: packet) // Notify Hello
                self.delegate?.didGetPacket(publisher: self, packet: successPacket) // Notify Success
            }
            return
        }
        
        // 2. Pending Handshake?
        if let _ = authenticator.getSalt(for: deviceId) {
            sendChallenge(deviceId: deviceId, connection: connection)
            DispatchQueue.main.async { self.delegate?.didGetPacket(publisher: self, packet: packet) }
            return
        }

        // 3. Auto-Trust?
        if authenticator.isAutoTrusted(connection: connection, localIPs: getLocalIPAddresses()) {
             self.authenticatedConnections.insert(ObjectIdentifier(connection))
             let successPacket = SnagPacket()
             successPacket.control = SnagControl(type: "auth_success", authMode: "cleartext")
             self.send(packet: successPacket, toConnection: connection)
             DispatchQueue.main.async {
                 self.delegate?.didGetPacket(publisher: self, packet: packet)
                 self.delegate?.didGetPacket(publisher: self, packet: successPacket)
             }
             return
        }
        
        // 4. Start Handshake
        sendChallenge(deviceId: deviceId, connection: connection)
        DispatchQueue.main.async {
            self.delegate?.didGetPacket(publisher: self, packet: packet)
            SnagController.shared.publisherStatus = "Waiting for Auth: \(packet.device?.deviceName ?? "Unknown")"
        }
    }
    
    private func sendChallenge(deviceId: String, connection: NWConnection) {
        let saltHex = authenticator.generateSalt(for: deviceId)
        let challengePacket = SnagPacket()
        challengePacket.control = SnagControl(type: "auth_required", salt: saltHex)
        self.send(packet: challengePacket, toConnection: connection)
    }
    
    private func handleAuthVerify(packet: SnagPacket, connection: NWConnection) {
        guard let hash = packet.control?.authHash, let deviceId = (packet.device?.deviceId ?? packet.control?.deviceId)?.lowercased() else { return }
        authenticator.registerPendingVerification(deviceId: deviceId, hash: hash)
        
        if let cachedPIN = authenticator.getCachedPIN(for: deviceId) {
             let result = self.authorizeDeviceLocked(deviceId: deviceId, pin: cachedPIN)
             if result {
                 // Notify UI of the success even if it was automated
                 let successPacket = SnagPacket()
                 successPacket.control = SnagControl(type: "auth_success", authMode: "encrypted")
                 successPacket.device = packet.device
                 successPacket.project = packet.project
                 DispatchQueue.main.async { self.delegate?.didGetPacket(publisher: self, packet: successPacket) }
                 return
             } else {
                 // ONLY remove PIN if it was WRONG, not if verify state was missing (salt etc)
                 // If salt is missing, authorizeDeviceLocked returns false without checking PIN.
                 // We can check if verification was even possible.
                 if authenticator.getSalt(for: deviceId) != nil {
                     print("SnagPublisher: Auto-auth failed with cached PIN for \(deviceId). Removing PIN.")
                     store.removeKnownPIN(deviceId: deviceId)
                 }
             }
        }
        
        DispatchQueue.main.async { self.delegate?.didGetPacket(publisher: self, packet: packet) }
    }
    
    private func handleEncryptedData(packet: SnagPacket, connection: NWConnection) {
        let deviceId = (packet.device?.deviceId ?? packet.control?.deviceId ?? deviceConnections.first(where: { $0.value === connection })?.key)?.lowercased()
        guard let resolvedDeviceId = deviceId else { return }
        
        do {
            if let decryptedPacket = try authenticator.decrypt(packet: packet, deviceId: resolvedDeviceId) {
                DispatchQueue.main.async { self.delegate?.didGetPacket(publisher: self, packet: decryptedPacket) }
            }
        } catch {
            print("SnagPublisher: Decryption failed")
        }
    }
    
    func authorizeDevice(deviceId: String, pin: String) -> Bool {
        return queue.sync { authorizeDeviceLocked(deviceId: deviceId, pin: pin) }
    }
    
    private func authorizeDeviceLocked(deviceId: String, pin: String) -> Bool {
        return authenticator.authorizeDeviceLocked(
            deviceId: deviceId,
            pin: pin,
            onAuthenticated: { conn in self.authenticatedConnections.insert(ObjectIdentifier(conn)) },
            sendPacket: { packet, conn in self.send(packet: packet, toConnection: conn) },
            getConnection: { id in self.deviceConnections[id] }
        )
    }
    
    func getLockoutStatus(deviceId: String) -> (locked: Bool, remainingSeconds: Int?) {
        return queue.sync { authenticator.getLockoutStatus(deviceId: deviceId) }
    }

    func stopPublishing() {
        queue.async { self.stopPublishingLocked() }
    }

    private func stopPublishingLocked() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        deviceConnections.removeAll()
        authenticatedConnections.removeAll()
        authenticator.reset()
    }
    
    private func removeConnection(_ connection: NWConnection) {
        self.connections.removeAll { $0 === connection }
        self.deviceConnections = self.deviceConnections.filter { $0.value !== connection }
        self.authenticatedConnections.remove(ObjectIdentifier(connection))
    }
    
    // MARK: - Helpers
    
    private func lengthOf(data: Data) -> Int? {
        guard data.count >= 8 else { return nil }
        let length = data.withUnsafeBytes { $0.load(as: UInt64.self) }
        return (length > 0 && length <= 50_000_000) ? Int(length) : nil
    }

    private func send(packet: SnagPacket, toConnection connection: NWConnection) {
        do {
            let data = try jsonEncoder.encode(packet)
            var length = UInt64(data.count)
            var buffer = Data(bytes: &length, count: 8)
            buffer.append(data)
            connection.send(content: buffer, completion: .contentProcessed { _ in })
        } catch { print("SnagPublisher: Encode error") }
    }
    
    func send(packet: SnagPacket, toDeviceId deviceId: String) {
        queue.async {
            guard let conn = self.deviceConnections[deviceId], conn.state == .ready else { return }
            self.send(packet: packet, toConnection: conn)
        }
    }
    
    func broadcast(packet: SnagPacket) {
        queue.async {
            for (_, conn) in self.deviceConnections where conn.state == .ready {
                self.send(packet: packet, toConnection: conn)
            }
        }
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

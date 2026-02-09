import Foundation
import Network
import CryptoKit
import CommonCrypto

class SnagBrowser: NSObject {
    
    weak var configuration: SnagConfiguration?
    
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private let pendingPackets = SnagBoundedQueue<SnagPacket>(maxSize: 100)
    private var discoveredEndpoints: Set<NWEndpoint> = []
    private var connectingEndpoints: Set<NWEndpoint> = []

    
    private var connectionKeys: [ObjectIdentifier: SymmetricKey] = [:]
    private var connectionAuthModes: [ObjectIdentifier: String] = [:] // "encrypted", "cleartext"
    
    private let queue = DispatchQueue(label: "com.snag.browser.queue")
    
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    
    init(configuration: SnagConfiguration) {
        super.init()
        self.configuration = configuration
    }

    var didConnect: (() -> Void)?
    var didReceivePacket: ((SnagPacket) -> Void)?

    func start() {
        self.startBrowsing()
    }
    
    func startBrowsing() {
        queue.async {
            self.stopBrowsingLocked()
            
            guard let type = self.configuration?.netserviceType else { return }
            let domain = (self.configuration?.netserviceDomain?.isEmpty ?? true) ? "local" : (self.configuration?.netserviceDomain ?? "local")
            
            let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: domain)
            let browser = NWBrowser(for: descriptor, using: .tcp)
            
            browser.browseResultsChangedHandler = { [weak self] results, changes in
                self?.handleResultsChanged(results: results)
            }
            
            browser.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    print("SnagBrowser: Browser failed with error: \(error)")
                    self.resetAndBrowse()
                default:
                    break
                }
            }
            
            browser.start(queue: self.queue)
            self.browser = browser
        }
    }
    
    private func handleResultsChanged(results: Set<NWBrowser.Result>) {
        queue.async {
            print("SnagBrowser: Browser results changed. Found \(results.count) results.")
            self.discoveredEndpoints = Set(results.map { $0.endpoint })
            for endpoint in self.discoveredEndpoints {
                let existingConnections = self.connections.filter { $0.endpoint == endpoint }
                let hasReadyConnection = existingConnections.contains { $0.state == .ready }
                
                if !hasReadyConnection {
                    // Proactively remove any stagnant connections for this endpoint
                    self.connections.removeAll { $0.endpoint == endpoint && $0.state != .ready }
                    self.connect(with: endpoint)
                }
            }
        }
    }
    
    private func connect(with endpoint: NWEndpoint) {
        connectingEndpoints.insert(endpoint)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.noDelay = true // Disable Nagle's algorithm for immediate sending
        
        let serverKey = trustKey(for: endpoint)
        
        let params: NWParameters
        if self.configuration?.isSecurityEnabled ?? false {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { [weak self] (_, sec_trust, completionHandler) in
                let decision = SnagTrustStore.shared.verifyOrTrust(serverKey: serverKey, secTrust: sec_trust)
                switch decision {
                case .trusted:
                    completionHandler(true)
                case let .mismatch(expected, actual):
                    DispatchQueue.main.async {
                        self?.configuration?.securityDelegate?.snagDidDetectIdentityMismatch(
                            serverKey: serverKey,
                            expectedFingerprint: expected,
                            actualFingerprint: actual,
                            recoveryHint: "Call Snag.resetTrustedServers() after confirming the trusted server identity."
                        )
                    }
                    completionHandler(false)
                case .invalid:
                    completionHandler(false)
                }
            }, self.queue)
            params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        } else {
            params = NWParameters(tls: nil, tcp: tcpOptions)
        }
        
        let connection = NWConnection(to: endpoint, using: params)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.queue.async {
                    self?.connectingEndpoints.remove(endpoint)
                }
                self?.handleConnected(connection)
            case .failed, .cancelled:
                self?.queue.async {
                    self?.connectingEndpoints.remove(endpoint)
                }
                self?.removeConnection(connection)
                self?.scheduleReconnect(endpoint: endpoint)
            case .waiting(let error):
                print("SnagBrowser: Connection to \(endpoint) is waiting: \(error). Reconnecting...")
                // If waiting for too long or in a bad state, we might want to recycle it
                // For now, just log it. NWConnection usually handles recovery.
            default:
                break
            }
        }
        
        connections.append(connection)
        connection.start(queue: queue)
    }
    
    private func handleConnected(_ connection: NWConnection) {
        queue.async {
            // New Handshake: Send Hello
            self.sendHello(on: connection)
            self.didConnect?() // Notify connectivity, but data isn't flowing yet
            self.receive(on: connection)
        }
    }

    private func sendHello(on connection: NWConnection) {
        let device = self.configuration?.device
        let helloControl = SnagControl(type: "hello", deviceId: device?.id)
        var helloPacket = SnagPacket()
        helloPacket.control = helloControl
        helloPacket.device = device
        helloPacket.project = self.configuration?.project
        
        // Send unencrypted
        self.sendRaw(packet: helloPacket, on: connection)
    }

    private func sendRaw(packet: SnagPacket, on connection: NWConnection) {
         do {
             let packetData = try self.encoder.encode(packet)
             var headerLength = UInt64(packetData.count)
             
             // Check max length
             if headerLength > 50_000_000 { return }
             
             let headerData = Data(bytes: &headerLength, count: MemoryLayout<UInt64>.size)
             var buffer = Data()
             buffer.append(headerData)
             buffer.append(packetData)
             self.sendData(buffer, on: connection)
         } catch {
             print("SnagBrowser: Encode error: \(error)")
         }
    }
    

    
    private func removeConnection(_ connection: NWConnection) {
        queue.async {
            self.connections.removeAll { $0 === connection }
        }
    }
    
    private func scheduleReconnect(endpoint: NWEndpoint) {
        queue.asyncAfter(deadline: .now() + 1.0) {
            guard self.discoveredEndpoints.contains(endpoint) else { return }
            let isAlreadyConnected = self.connections.contains { $0.endpoint == endpoint }
            let isConnecting = self.connectingEndpoints.contains(endpoint)
            guard !isAlreadyConnected && !isConnecting else { return }
            self.connect(with: endpoint)
        }
    }
    
    private func stopBrowsingLocked() {
        browser?.cancel()
        browser = nil
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        pendingPackets.clear()
        discoveredEndpoints.removeAll()
        connectingEndpoints.removeAll()
        connectionKeys.removeAll()
        connectionAuthModes.removeAll()
    }
    
    func resetAndBrowse() {
        startBrowsing()
    }
    
    private var pendingTaskCount: Int = 0
    private let counterLock = NSLock()
    private let MAX_PENDING_TASKS = 500
    


    private func enqueuePendingPacketLocked(_ packet: SnagPacket) {
        let dropped = pendingPackets.enqueue(packet)
        if dropped {
            print("SnagBrowser: Pre-auth queue full. Dropping oldest packet.")
        }
    }

    private func flushPendingPacketsLocked() {
        guard pendingPackets.snapshot().queuedPackets > 0 else { return }

        let readyConnections = connections.filter { $0.state == .ready }
        let authenticatedConnections = readyConnections.compactMap { connection -> (NWConnection, String)? in
            guard let mode = self.connectionAuthModes[ObjectIdentifier(connection)] else { return nil }
            return (connection, mode)
        }
        guard !authenticatedConnections.isEmpty else { return }

        let packets = pendingPackets.drain()
        guard !packets.isEmpty else { return }

        for packet in packets {
            for (connection, mode) in authenticatedConnections {
                sendPreparedPacketLocked(packet, on: connection, mode: mode)
            }
        }
    }
    
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] data, context, isComplete, error in
            if let error = error {
                print("SnagBrowser: Receive header error: \(error)")
                self?.removeConnection(connection)
                return
            }
            
            guard let data = data, data.count == 8 else {
                if isComplete { self?.removeConnection(connection) }
                return
            }
            
            guard let length = self?.lengthOf(data: data) else {
                print("SnagBrowser: Invalid length header")
                self?.removeConnection(connection)
                return
            }
            
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, context, isComplete, error in
                if let error = error {
                    print("SnagBrowser: Receive body error: \(error)")
                    self?.removeConnection(connection)
                    return
                }
                
                if let data = data {
                    self?.parseBody(data: data, from: connection)
                }
                
                if !isComplete {
                    self?.receive(on: connection)
                } else {
                    self?.removeConnection(connection)
                }
            }
        }
    }
    
    private func lengthOf(data: Data) -> Int? {
        if data.count < MemoryLayout<UInt64>.stride { return nil }
        var length: UInt64 = 0
        data.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                memcpy(&length, base, MemoryLayout<UInt64>.stride)
            }
        }
        if length == 0 || length > 50_000_000 { return nil }
        return Int(length)
    }
    
    private func parseBody(data: Data, from connection: NWConnection) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        do {
            let packet = try decoder.decode(SnagPacket.self, from: data)
            
            // Check for Control Packets (Handshake)
            if packet.control?.type == "auth_success" {
                handleAuthSuccess(packet: packet, connection: connection)
                return
            }
            
            DispatchQueue.main.async {
                self.didReceivePacket?(packet)
            }
        } catch {
            print("SnagBrowser: Parse error: \(error)")
        }
    }

    private func trustKey(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case let .service(name, type, domain, _):
            return "\(name.lowercased())|\(type.lowercased())|\(domain.lowercased())"
        case let .hostPort(host, port):
            return "\(host.debugDescription.lowercased()):\(port.rawValue)"
        default:
            return endpoint.debugDescription.lowercased()
        }
    }
    
    // MARK: - Handshake Handlers
    
    private func handleAuthSuccess(packet: SnagPacket, connection: NWConnection) {
        guard let mode = packet.control?.authMode else { return }
        
        self.connectionAuthModes[ObjectIdentifier(connection)] = mode
        print("SnagBrowser: Auth Success! Mode: \(mode)")
        
        // Flush pending packets now that we are authenticated
        self.flushPendingPacketsLocked()
    }

    private func sendData(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("SnagBrowser: Send error: \(error)")
                connection.cancel()
            }
        })
    }
    
    // Updated Send Logic with Encryption
    func send(packet: SnagPacket) {
        counterLock.lock()
        if pendingTaskCount >= MAX_PENDING_TASKS {
            counterLock.unlock()
            return
        }
        pendingTaskCount += 1
        counterLock.unlock()
        
        queue.async {
             defer {
                 self.counterLock.lock()
                 self.pendingTaskCount -= 1
                 self.counterLock.unlock()
             }
             
             // Prepare final packet (add project/device info)
             var finalPacket = packet
             if finalPacket.project == nil {
                 finalPacket.project = self.configuration?.project
             }
             if finalPacket.device == nil {
                 finalPacket.device = self.configuration?.device
             }
             
             // Check connections
             let readyConnections = self.connections.filter({ $0.state == .ready })

             let authenticatedConnections = readyConnections.compactMap { connection -> (NWConnection, String)? in
                 guard let mode = self.connectionAuthModes[ObjectIdentifier(connection)] else { return nil }
                 return (connection, mode)
             }

             if authenticatedConnections.isEmpty {
                 self.enqueuePendingPacketLocked(finalPacket)
                 return
             }

             for (connection, mode) in authenticatedConnections {
                 self.sendPreparedPacketLocked(finalPacket, on: connection, mode: mode)
             }
        }
    }

    private func sendPreparedPacketLocked(_ packet: SnagPacket, on connection: NWConnection, mode: String) {
        if mode == "encrypted" {
            guard let key = self.connectionKeys[ObjectIdentifier(connection)] else {
                print("SnagBrowser: Missing key for encrypted connection.")
                return
            }
            do {
                let plaintext = try self.encoder.encode(packet)
                let (ciphertext, nonce) = try SnagCrypto.encrypt(data: plaintext, key: key)

                var wrapperPacket = SnagPacket()
                wrapperPacket.control = SnagControl(type: "data", encryptedPayload: ciphertext, encryptedNonce: nonce)
                wrapperPacket.device = packet.device
                wrapperPacket.project = packet.project

                self.sendRaw(packet: wrapperPacket, on: connection)
            } catch {
                print("SnagBrowser: Encryption Error: \(error)")
            }
        } else {
            self.sendRaw(packet: packet, on: connection)
        }
    }

    func queueMetricsSnapshot() -> SnagQueueMetricsSnapshot {
        return pendingPackets.snapshot()
    }
}

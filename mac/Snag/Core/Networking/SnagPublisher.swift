import Cocoa
import Network

protocol SnagPublisherDelegate {
    func didGetPacket(publisher: SnagPublisher, packet: SnagPacket)
}

class SnagPublisher: NSObject {

    var delegate: SnagPublisherDelegate?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var authenticatedConnections: Set<ObjectIdentifier> = []
    private var deviceConnections: [String: NWConnection] = [:]
    
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
                    DispatchQueue.main.async {
                        SnagController.shared.publisherStatus = "Connected: \(connection.endpoint)"
                    }
                    self.receiveData(on: connection)
                case .failed(let error):
                    print("SnagPublisher: Connection failed: \(error)")
                    self.evictConnection(connection, reason: "state_failed")
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
            } else if let deviceId = (snagPacket.device?.deviceId ?? snagPacket.control?.deviceId)?.lowercased() {
                // Regular packet
                if isTrusted(connection: connection, packetType: type ?? "data") {
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
    
    private func isTrusted(connection: NWConnection, packetType: String) -> Bool {
        let isTrusted = authenticatedConnections.contains(ObjectIdentifier(connection))
        if SnagConfiguration.isSecurityEnabled && !isTrusted {
            print("SnagPublisher: Dropped unauthorized [\(packetType)] packet from \(connection.endpoint)")
            return false
        }
        return true
    }

    private func handleHello(packet: SnagPacket, connection: NWConnection) {
        guard let deviceId = (packet.device?.deviceId ?? packet.control?.deviceId)?.lowercased() else { return }
        
        // 0. Close existing connection for this device if it's different
        if let existing = self.deviceConnections[deviceId], existing !== connection {
            print("SnagPublisher: Closing stale connection for \(deviceId)")
            self.removeConnection(existing)
            existing.cancel()
        }
        
        self.deviceConnections[deviceId] = connection

        self.authenticatedConnections.insert(ObjectIdentifier(connection))

        let successPacket = SnagPacket()
        successPacket.control = SnagControl(type: "auth_success", deviceId: deviceId, authMode: "cleartext")
        successPacket.device = packet.device
        successPacket.project = packet.project
        self.send(packet: successPacket, toConnection: connection)

        DispatchQueue.main.async {
            self.delegate?.didGetPacket(publisher: self, packet: packet)
            self.delegate?.didGetPacket(publisher: self, packet: successPacket)
            SnagController.shared.publisherStatus = "Authenticated: \(packet.device?.deviceName ?? "Unknown")"
        }
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
        guard connection.state == .ready else {
            evictConnection(connection, reason: "send_on_non_ready_connection")
            return
        }

        do {
            let data = try jsonEncoder.encode(packet)
            var length = UInt64(data.count)
            var buffer = Data(bytes: &length, count: 8)
            buffer.append(data)
            connection.send(content: buffer, completion: .contentProcessed { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.queue.async {
                        print("SnagPublisher: Send failed (\(connection.endpoint)): \(error)")
                        self.evictConnection(connection, reason: "send_failed")
                    }
                }
            })
        } catch { print("SnagPublisher: Encode error") }
    }
    
    func send(packet: SnagPacket, toDeviceId deviceId: String) {
        queue.async {
            guard let conn = self.deviceConnections[deviceId.lowercased()] else { return }
            guard conn.state == .ready else {
                self.evictConnection(conn, reason: "device_send_non_ready")
                return
            }
            self.send(packet: packet, toConnection: conn)
        }
    }
    
    func broadcast(packet: SnagPacket) {
        queue.async {
            let connections = Array(self.deviceConnections.values)
            for conn in connections where conn.state == .ready {
                self.send(packet: packet, toConnection: conn)
            }
            for conn in connections where conn.state != .ready {
                self.evictConnection(conn, reason: "broadcast_non_ready")
            }
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

    private func evictConnection(_ connection: NWConnection, reason: String) {
        print("SnagPublisher: Evicting connection (\(connection.endpoint)) reason=\(reason)")
        self.removeConnection(connection)
        connection.cancel()
    }
}

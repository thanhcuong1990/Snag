import Cocoa
import Network

protocol SnagPublisherDelegate {
    func didGetPacket(publisher: SnagPublisher, packet: SnagPacket)
}

class SnagPublisher: NSObject {

    var delegate: SnagPublisherDelegate?
    
    private enum ListenerPurpose {
        case primarySecure
        case primaryCleartext
    }

    private var primaryListener: NWListener?
    private var legacyPublisher: SnagLegacyPublisher?
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

    private var pendingMainPackets: [SnagPacket] = []
    private var mainFlushScheduled = false
    private static let mainCoalesceInterval: DispatchTimeInterval = .milliseconds(16)
    
    func startPublishing() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopPublishingLocked()

            guard let primaryPort = NWEndpoint.Port(rawValue: UInt16(SnagConfiguration.netServicePort)) else {
                print("SnagPublisher: Invalid primary port \(SnagConfiguration.netServicePort)")
                self.schedulePublishRetryLocked()
                return
            }

            if SnagConfiguration.isSecurityEnabled {
                self.primaryListener = self.startListenerLocked(
                    purpose: .primarySecure,
                    port: primaryPort,
                    serviceName: SnagConfiguration.netServiceName,
                    useTLS: true,
                    retryOnFailure: true
                )

                self.legacyPublisher = SnagLegacyPublisher(queue: self.queue)
                self.legacyPublisher?.delegate = self
                self.legacyPublisher?.start()
                
            } else {
                self.primaryListener = self.startListenerLocked(
                    purpose: .primaryCleartext,
                    port: primaryPort,
                    serviceName: SnagConfiguration.netServiceName,
                    useTLS: false,
                    retryOnFailure: true
                )
            }
        }
    }

    private func startListenerLocked(
        purpose: ListenerPurpose,
        port: NWEndpoint.Port,
        serviceName: String,
        useTLS: Bool,
        retryOnFailure: Bool
    ) -> NWListener? {
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.noDelay = true

            let params: NWParameters
            if useTLS {
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

            let listener = try NWListener(using: params, on: port)

            listener.service = NWListener.Service(
                name: serviceName.isEmpty ? nil : serviceName,
                type: SnagConfiguration.netServiceType,
                domain: SnagConfiguration.netServiceDomain.isEmpty ? nil : SnagConfiguration.netServiceDomain
            )

            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerStateUpdate(
                    state,
                    purpose: purpose,
                    port: port,
                    retryOnFailure: retryOnFailure
                )
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.setupConnection(connection, purpose: purpose)
            }

            listener.start(queue: self.queue)
            return listener
        } catch {
            print("SnagPublisher: Failed to start \(purpose) listener on \(port): \(error)")
            if retryOnFailure {
                schedulePublishRetryLocked()
            }
            return nil
        }
    }

    private func handleListenerStateUpdate(
        _ state: NWListener.State,
        purpose: ListenerPurpose,
        port: NWEndpoint.Port,
        retryOnFailure: Bool
    ) {
        switch state {
        case .ready:
            break
        case .failed(let error):
            print("SnagPublisher: \(purpose) listener failed on \(port): \(error)")
            self.primaryListener = nil

            if retryOnFailure {
                schedulePublishRetryLocked()
            }
        default:
            break
        }
    }

    private func setupConnection(_ connection: NWConnection, purpose: ListenerPurpose) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.queue.async {
                switch state {
                case .ready:
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
            let deviceId = (snagPacket.device?.deviceId ?? snagPacket.control?.deviceId)?.lowercased()
            
            if type == "hello" {
                handleHello(packet: snagPacket, connection: connection)
                return
            }

            if isTrusted(connection: connection, packetType: type ?? "data") {
                forwardPacketToUI(snagPacket, from: connection, deviceId: deviceId)
                return
            }
        } catch {
            print("SnagPublisher: parse error: \(error)")
        }
    }

    private func forwardPacketToUI(_ packet: SnagPacket, from connection: NWConnection, deviceId: String?) {
        if packet.device?.deviceId == nil, let deviceId = deviceId {
            if packet.device == nil {
                packet.device = SnagDeviceModel()
            }
            packet.device?.deviceId = deviceId
        }

        if let deviceId = deviceId {
            self.deviceConnections[deviceId] = connection
        }

        self.enqueuePacketForMainLocked(packet)
    }

    // Coalesce per-packet main-thread hops into batches to reduce dispatch overhead under bursts.
    private func enqueuePacketForMainLocked(_ packet: SnagPacket) {
        self.pendingMainPackets.append(packet)
        if !self.mainFlushScheduled {
            self.mainFlushScheduled = true
            self.queue.asyncAfter(deadline: .now() + Self.mainCoalesceInterval) { [weak self] in
                self?.flushMainPacketsLocked()
            }
        }
    }

    private func flushMainPacketsLocked() {
        self.mainFlushScheduled = false
        guard !self.pendingMainPackets.isEmpty else { return }
        let batch = self.pendingMainPackets
        self.pendingMainPackets.removeAll(keepingCapacity: true)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for packet in batch {
                self.delegate?.didGetPacket(publisher: self, packet: packet)
            }
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

        self.enqueuePacketForMainLocked(packet)
        self.enqueuePacketForMainLocked(successPacket)
    }

    func stopPublishing() {
        queue.async { self.stopPublishingLocked() }
    }

    private func stopPublishingLocked() {
        primaryListener?.cancel()
        primaryListener = nil
        legacyPublisher?.stop()
        legacyPublisher = nil

        connections.forEach { $0.cancel() }
        connections.removeAll()
        deviceConnections.removeAll()
        authenticatedConnections.removeAll()
        flushMainPacketsLocked()
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

extension SnagPublisher: SnagLegacyPublisherDelegate {
    func legacyPublisher(_ publisher: SnagLegacyPublisher, didPromoteConnection connection: NWConnection, deviceId: String?, packet: SnagPacket) {
        // The connection is already started and processing data in LegacyPublisher
        // We need to take over management of this connection.
        
        self.queue.async {
            print("SnagPublisher: Taking over legacy connection from \(connection.endpoint)")
            
            // Add to our lists
            self.connections.append(connection)
            self.authenticatedConnections.insert(ObjectIdentifier(connection))
            
            if let deviceId = deviceId {
                self.deviceConnections[deviceId] = connection
                
                 // Send Auth Success
                let successPacket = SnagPacket()
                successPacket.control = SnagControl(type: "auth_success", deviceId: deviceId, authMode: "cleartext")
                successPacket.device = packet.device
                successPacket.project = packet.project
                self.send(packet: successPacket, toConnection: connection)
            }
            
            // Set up our own state handler (replacing the one from legacy publisher?)
            // Actually, we should probably just monitor it.
            // But wait, the receive loop is running in LegacyPublisher.
            // We need to ensure that subsequent reads happen here.
            
            // In SnagLegacyPublisher, we stopped reading after promoting.
            // So we need to start reading here.
            
            connection.stateUpdateHandler = { [weak self] state in
                 guard let self = self else { return }
                 self.queue.async {
                     switch state {
                     case .failed(let error):
                         print("SnagPublisher: Legacy Connection failed: \(error)")
                         self.evictConnection(connection, reason: "legacy_state_failed")
                     case .cancelled:
                         self.removeConnection(connection)
                     default:
                         break
                     }
                 }
             }
            
            self.receiveData(on: connection)
            
            // Process the packet that triggered promotion
            self.forwardPacketToUI(packet, from: connection, deviceId: deviceId)
        }
    }
    
    func legacyPublisher(_ publisher: SnagLegacyPublisher, didFailWithError error: Error) {
        print("SnagPublisher: Legacy publisher error: \(error)")
    }
}

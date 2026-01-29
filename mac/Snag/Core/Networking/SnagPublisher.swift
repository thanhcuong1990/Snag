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
    private var manuallyAuthorizedDeviceIds: Set<String> = []
    private let queue = DispatchQueue(label: "com.snag.publisher.queue")
    private let authorizedDevicesKey = "SnagAuthorizedDeviceIds"

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
            
            // Security Check
            if SnagConfiguration.isSecurityEnabled {
                let isTrusted = authenticatedConnections.contains(ObjectIdentifier(connection))
                var isAuthorized = false
                
                if let deviceId = snagPacket.device?.deviceId {
                    isAuthorized = manuallyAuthorizedDeviceIds.contains(deviceId)
                }
                
                if !isTrusted && !isAuthorized {
                    // Mark packet as unauthenticated. Manual authorization via the Mac app (using the PIN) is required.
                    snagPacket.isUnauthenticated = true
                }
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
    
    func authorizeDevice(deviceId: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.manuallyAuthorizedDeviceIds.insert(deviceId)
            self.saveAuthorizedDevices()
            
            if let connection = self.deviceConnections[deviceId] {
                self.authenticatedConnections.insert(ObjectIdentifier(connection))
            }
            
            print("SnagPublisher: Device \(deviceId) manually authorized")
        }
    }

    private func loadAuthorizedDevices() {
        let saved = UserDefaults.standard.stringArray(forKey: authorizedDevicesKey) ?? []
        self.manuallyAuthorizedDeviceIds = Set(saved)
    }

    private func saveAuthorizedDevices() {
        UserDefaults.standard.set(Array(self.manuallyAuthorizedDeviceIds), forKey: authorizedDevicesKey)
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


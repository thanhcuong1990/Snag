import Foundation
import Network

class SnagBrowser: NSObject {
    
    weak var configuration: SnagConfiguration?
    
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var pendingBuffers: [Data] = []
    private var discoveredEndpoints: Set<NWEndpoint> = []
    private var connectingEndpoints: Set<NWEndpoint> = []
    private let queue = DispatchQueue(label: "com.snag.browser.queue")
    
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    
    private let MAX_OFFLINE_BUFFER = 50
    
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
        
        
        let params: NWParameters
        if self.configuration?.isSecurityEnabled ?? false {
            let tlsOptions = NWProtocolTLS.Options()
            // Allow self-signed certificates
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { (metadata, sec_trust, completionHandler) in
                completionHandler(true)
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
            self.sendAuthIfRequired(on: connection)
            self.flushPendingLocked()
            self.didConnect?()
            self.receive(on: connection)
        }
    }
    
    private func sendAuthIfRequired(on connection: NWConnection) {
        guard let config = self.configuration, config.isSecurityEnabled else { return }
        
        let authControl = SnagControl(type: "authPIN", authPIN: config.securityPIN)
        var authPacket = SnagPacket()
        authPacket.control = authControl
        authPacket.project = config.project
        authPacket.device = config.device
        
        do {
            let packetData = try self.encoder.encode(authPacket)
            var headerLength = UInt64(packetData.count)
            let headerData = Data(bytes: &headerLength, count: MemoryLayout<UInt64>.size)
            
            var buffer = Data()
            buffer.append(headerData)
            buffer.append(packetData)
            
            self.sendData(buffer, on: connection)
        } catch {
            print("SnagBrowser: Auth encoding error: \(error)")
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
        pendingBuffers.removeAll()
        discoveredEndpoints.removeAll()
        connectingEndpoints.removeAll()
    }
    
    func resetAndBrowse() {
        startBrowsing()
    }
    
    private var pendingTaskCount: Int = 0
    private let counterLock = NSLock()
    private let MAX_PENDING_TASKS = 500
    
    // MARK: - Sending Packet
    
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
            
            do {
                var finalPacket = packet
                if finalPacket.project == nil {
                    finalPacket.project = self.configuration?.project
                }
                if finalPacket.device == nil {
                    finalPacket.device = self.configuration?.device
                }
                
                let packetData = try self.encoder.encode(finalPacket)
                
                var headerLength = UInt64(packetData.count)
                let headerData = Data(bytes: &headerLength, count: MemoryLayout<UInt64>.size)
                
                var buffer = Data()
                buffer.append(headerData)
                buffer.append(packetData)
                
                let readyConnections = self.connections.filter({ $0.state == .ready })
                if readyConnections.isEmpty {
                    if self.pendingBuffers.count >= self.MAX_OFFLINE_BUFFER {
                        self.pendingBuffers.removeFirst()
                    }
                    self.pendingBuffers.append(buffer)
                } else {
                    for connection in readyConnections {
                        self.sendData(buffer, on: connection)
                    }
                }
                
            } catch {
                print("SnagBrowser: Encoding error: \(error)")
            }
        }
    }
    
    private func sendData(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("SnagBrowser: Send error: \(error)")
                connection.cancel()
            }
        })
    }

    private func flushPendingLocked() {
        guard !pendingBuffers.isEmpty else { return }
        let readyConnections = connections.filter { $0.state == .ready }
        guard !readyConnections.isEmpty else { return }
        
        let buffers = pendingBuffers
        pendingBuffers.removeAll()
        
        for buffer in buffers {
            for connection in readyConnections {
                sendData(buffer, on: connection)
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
                    self?.parseBody(data: data)
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
    
    private func parseBody(data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        do {
            let packet = try decoder.decode(SnagPacket.self, from: data)
            DispatchQueue.main.async {
                self.didReceivePacket?(packet)
            }
        } catch {
            print("SnagBrowser: Parse error: \(error)")
        }
    }
}

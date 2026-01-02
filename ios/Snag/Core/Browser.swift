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
        let connection = NWConnection(to: endpoint, using: .tcp)
        
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
            self.flushPendingLocked()
            self.didConnect?()
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
    
    // MARK: - Sending Packet
    
    func send(packet: SnagPacket) {
        queue.async {
            do {
                let packetData = try self.encoder.encode(packet)
                
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
}

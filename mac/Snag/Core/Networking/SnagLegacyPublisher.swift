import Cocoa
import Network

protocol SnagLegacyPublisherDelegate: AnyObject {
    func legacyPublisher(_ publisher: SnagLegacyPublisher, didPromoteConnection connection: NWConnection, deviceId: String?, packet: SnagPacket)
    func legacyPublisher(_ publisher: SnagLegacyPublisher, didFailWithError error: Error)
}

class SnagLegacyPublisher: NSObject {
    
    weak var delegate: SnagLegacyPublisherDelegate?
    
    private var listener: NWListener?
    private let queue: DispatchQueue
    
    init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    func start() {
        guard let port = self.legacyCompatibilityPort() else {
            print("SnagLegacyPublisher: Failed to start listener: invalid port")
            return
        }
        
        let serviceName = self.legacyCompatibilityServiceName()
        
        do {
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.enableKeepalive = true
            tcpOptions.noDelay = true
            
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.includePeerToPeer = true
            
            let listener = try NWListener(using: params, on: port)
            
            listener.service = NWListener.Service(
                name: serviceName.isEmpty ? nil : serviceName,
                type: SnagConfiguration.netServiceType,
                domain: SnagConfiguration.netServiceDomain.isEmpty ? nil : SnagConfiguration.netServiceDomain
            )
            
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerStateUpdate(state, port: port)
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener.start(queue: self.queue)
            self.listener = listener
            
            print("SnagLegacyPublisher: Started listening on port \(port.rawValue)")
            
        } catch {
            print("SnagLegacyPublisher: Failed to start listener on \(port): \(error)")
            delegate?.legacyPublisher(self, didFailWithError: error)
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    var port: NWEndpoint.Port? {
        return listener?.port
    }
    
    private func handleListenerStateUpdate(_ state: NWListener.State, port: NWEndpoint.Port) {
        switch state {
        case .ready:
            print("SnagLegacyPublisher: Listener ready on \(port)")
        case .failed(let error):
            print("SnagLegacyPublisher: Listener failed on \(port): \(error)")
            delegate?.legacyPublisher(self, didFailWithError: error)
            stop()
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: self.queue)
        self.receiveData(on: connection)
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

                if bodyError != nil {
                    connection.cancel()
                    return
                }
                
                if let bodyData = bodyData {
                    self.processReceivedData(bodyData, from: connection)
                }
                
                // We don't continue receiving loop here because we either promote or drop for legacy
                if !bodyIsComplete {
                     // For legacy promotion, we might hand off the connection, so we stop reading here?
                     // Actually, the original code promotes and then forwards packet.
                     // But if it's promoted, `SnagPublisher` takes over.
                } else {
                    connection.cancel()
                }
            }
        }
    }
    
    private func processReceivedData(_ data: Data, from connection: NWConnection) {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .secondsSince1970
        
        do {
            let snagPacket = try jsonDecoder.decode(SnagPacket.self, from: data)
            let deviceId = (snagPacket.device?.deviceId ?? snagPacket.control?.deviceId)?.lowercased()
             
            if shouldAcceptLegacyPacket(snagPacket) {
                 print("SnagLegacyPublisher: Promoting legacy connection from \(connection.endpoint)")
                delegate?.legacyPublisher(self, didPromoteConnection: connection, deviceId: deviceId, packet: snagPacket)
            } else {
                print("SnagLegacyPublisher: Ignored non-legacy packet from \(connection.endpoint)")
                connection.cancel()
            }
        } catch {
             print("SnagLegacyPublisher: Parse error: \(error)")
             connection.cancel()
        }
    }
    
    // MARK: - Legacy Logic
    
    private func shouldAcceptLegacyPacket(_ packet: SnagPacket) -> Bool {
        if packet.requestInfo != nil || packet.log != nil {
            return true
        }

        // Older Android clients may send an initial metadata-only packet
        // (device/project without control/request/log) before any request data.
        if packet.device != nil || packet.project != nil {
            return true
        }

        guard let controlType = packet.control?.type else { return false }
        let legacyControlTypes: Set<String> = [
            "appInfoResponse",
            "logStreamingControl",
            "logStreamingStatusRequest",
            "logStreamingStatusResponse",
            "appInfoRequest",
            "ping"
        ]
        return legacyControlTypes.contains(controlType)
    }

    private func legacyCompatibilityPort() -> NWEndpoint.Port? {
        let candidate = Int(SnagConfiguration.netServicePort) + 1
        guard candidate > 0 && candidate <= Int(UInt16.max) else { return nil }
        return NWEndpoint.Port(rawValue: UInt16(candidate))
    }

    private func legacyCompatibilityServiceName() -> String {
        if SnagConfiguration.netServiceName.isEmpty {
            return "SnagLegacy"
        }
        return "\(SnagConfiguration.netServiceName)-legacy"
    }
    
    private func lengthOf(data: Data) -> Int? {
        guard data.count >= 8 else { return nil }
        let length = data.withUnsafeBytes { $0.load(as: UInt64.self) }
        return (length > 0 && length <= 50_000_000) ? Int(length) : nil
    }
}

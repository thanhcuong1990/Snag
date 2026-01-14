import Cocoa
import Network

protocol SnagPublisherDelegate {
    func didGetPacket(publisher: SnagPublisher, packet: SnagPacket)
}

class SnagPublisher: NSObject {

    var delegate: SnagPublisherDelegate?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var deviceConnections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.snag.publisher.queue")
    
    func startPublishing() {
        queue.async {
            self.stopPublishingLocked()
            
            do {
                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.enableKeepalive = true
                tcpOptions.noDelay = true // Disable Nagle's algorithm for immediate sending
                
                let params = NWParameters(tls: nil, tcp: tcpOptions)
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
                    case .failed(let error):
                        print("SnagPublisher: Listener failed with error: \(error)")
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
            switch state {
            case .ready:
                self?.receiveData(on: connection)
            case .failed, .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        
        queue.async {
            self.connections.append(connection)
            connection.start(queue: self.queue)
        }
    }

    private func receiveData(on connection: NWConnection) {
        // First, read the 8-byte length header
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] data, context, isComplete, error in
            if let error = error {
                print("SnagPublisher: Receive header error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, data.count == 8 else {
                if isComplete { connection.cancel() }
                return
            }
            
            guard let length = self?.lengthOf(data: data) else {
                print("SnagPublisher: Invalid length header")
                connection.cancel()
                return
            }
            
            // Now read the body of specified length
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, context, isComplete, error in
                if let error = error {
                    print("SnagPublisher: Receive body error: \(error)")
                    connection.cancel()
                    return
                }
                
                if let data = data {
                    self?.parseBody(data: data, from: connection)
                }
                
                // Continue reading next packet if not closed
                if !isComplete {
                    self?.receiveData(on: connection)
                } else {
                    connection.cancel()
                }
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        queue.async {
            self.connections.removeAll { $0 === connection }
            // Clean up deviceConnections to prevent stale connection references
            self.deviceConnections = self.deviceConnections.filter { $0.value !== connection }
        }
    }

    private func stopPublishingLocked() {
        listener?.cancel()
        listener = nil
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        deviceConnections.removeAll()
    }
    
    private func lengthOf(data: Data) -> Int? {
        if data.count < MemoryLayout<UInt64>.stride {
            return nil
        }
        var length: UInt64 = 0
        data.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                memcpy(&length, base, MemoryLayout<UInt64>.stride)
            }
        }
        if length == 0 || length > 50_000_000 {
            return nil
        }
        if length > UInt64(Int.max) {
            return nil
        }
        return Int(length)
    }
    
    private func parseBody(data: Data, from connection: NWConnection) {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .secondsSince1970
        
        do {
            let snagPacket = try jsonDecoder.decode(SnagPacket.self, from: data)
            
            if let deviceId = snagPacket.device?.deviceId {
                queue.async {
                    self.deviceConnections[deviceId] = connection
                }
            }
            
            DispatchQueue.main.async {
                self.delegate?.didGetPacket(publisher: self, packet: snagPacket)
            }
        } catch {
            print("SnagPublisher: Parse error: \(error)")
        }
    }
    
    func send(packet: SnagPacket, toDeviceId deviceId: String) {
        queue.async {
            guard let connection = self.deviceConnections[deviceId], connection.state == .ready else {
                print("SnagPublisher: No ready connection for device \(deviceId)")
                return
            }
            
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                let packetData = try encoder.encode(packet)
                
                var headerLength = UInt64(packetData.count)
                let headerData = Data(bytes: &headerLength, count: MemoryLayout<UInt64>.size)
                
                var buffer = Data()
                buffer.append(headerData)
                buffer.append(packetData)
                
                connection.send(content: buffer, completion: .contentProcessed { error in
                    if let error = error {
                        print("SnagPublisher: Send error to device \(deviceId): \(error)")
                        connection.cancel()
                    }
                })
            } catch {
                print("SnagPublisher: Encoding error for device \(deviceId): \(error)")
            }
        }
    }
    
    func broadcast(packet: SnagPacket) {
        queue.async {
            for connection in self.connections where connection.state == .ready {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .secondsSince1970
                    let packetData = try encoder.encode(packet)
                    
                    var headerLength = UInt64(packetData.count)
                    let headerData = Data(bytes: &headerLength, count: MemoryLayout<UInt64>.size)
                    
                    var buffer = Data()
                    buffer.append(headerData)
                    buffer.append(packetData)
                    
                    connection.send(content: buffer, completion: .contentProcessed { error in
                        if let error = error {
                            print("SnagPublisher: Broadcast send error: \(error)")
                            connection.cancel()
                        }
                    })
                } catch {
                    print("SnagPublisher: Broadcast encoding error: \(error)")
                }
            }
        }
    }
    
    private var publishRetryScheduled = false
    private func schedulePublishRetryLocked() {
        if publishRetryScheduled { return }
        publishRetryScheduled = true
        queue.asyncAfter(deadline: .now() + 1.0) {
            self.publishRetryScheduled = false
            self.startPublishing()
        }
    }
}

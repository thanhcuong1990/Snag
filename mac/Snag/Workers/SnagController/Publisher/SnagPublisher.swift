import Cocoa
import Network

protocol SnagPublisherDelegate {
    func didGetPacket(publisher: SnagPublisher, packet: SnagPacket)
}

class SnagPublisher: NSObject {

    var delegate: SnagPublisherDelegate?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.snag.publisher.queue")
    
    func startPublishing() {
        queue.async {
            self.stopPublishingLocked()
            
            do {
                let params = NWParameters.tcp
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
                self?.removeConnection(connection)
                return
            }
            
            guard let data = data, data.count == 8 else {
                if isComplete { self?.removeConnection(connection) }
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
                    self?.removeConnection(connection)
                    return
                }
                
                if let data = data {
                    self?.parseBody(data: data)
                }
                
                // Continue reading next packet if not closed
                if !isComplete {
                    self?.receiveData(on: connection)
                } else {
                    self?.removeConnection(connection)
                }
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        queue.async {
            self.connections.removeAll { $0 === connection }
        }
    }

    private func stopPublishingLocked() {
        listener?.cancel()
        listener = nil
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
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
    
    private func parseBody(data: Data) {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .secondsSince1970
        
        do {
            let snagPacket = try jsonDecoder.decode(SnagPacket.self, from: data)
            DispatchQueue.main.async {
                self.delegate?.didGetPacket(publisher: self, packet: snagPacket)
            }
        } catch {
            print("SnagPublisher: Parse error: \(error)")
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

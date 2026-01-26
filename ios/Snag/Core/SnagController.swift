import Foundation

class SnagController: SnagSessionInjectorDelegate, SnagConnectionInjectorDelegate {
    
    var configuration: SnagConfiguration
    var browser: SnagBrowser
    
    var sessionInjector: SnagSessionInjector?
    var connectionInjector: SnagConnectionInjector?
    
    var carriers: [SnagCarrier] = []
    
    let queue = DispatchQueue(label: "com.snag.injectController")
    
    init(configuration: SnagConfiguration) {
        self.configuration = configuration
        self.browser = SnagBrowser(configuration: configuration)
        
        self.sessionInjector = SnagSessionInjector(delegate: self)
        // self.connectionInjector = SnagConnectionInjector(delegate: self)
        
        self.carriers = []
        
        // Defer heavy metadata calls to background queue
        self.queue.async {
            if self.configuration.project?.appIcon == nil {
                self.configuration.project?.appIcon = SnagUtility.appIcon()
            }
            if self.configuration.device?.ipAddress == nil {
                self.configuration.device?.ipAddress = SnagUtility.ipAddress()
            }
        }
        
        self.browser.didConnect = { [weak self] in
            self?.performBlock {
                self?.sendHelloPacket()
                self?.sendHandshakePackets()
            }
        }
        
        self.browser.didReceivePacket = { [weak self] packet in
            self?.handleReceivedPacket(packet)
        }
        
        self.browser.start()
    }
    
    private func sendHelloPacket() {
        let packet = SnagPacket(
            id: UUID().uuidString,
            requestInfo: nil,
            project: self.configuration.project,
            device: self.configuration.device
        )
        self.browser.send(packet: packet)
    }
    
    private func performBlock(_ block: @escaping () -> Void) {
        queue.async(execute: block)
    }
    
    private func carrier(with task: URLSessionTask) -> SnagCarrier? {
        if let existing = self.carriers.first(where: { $0.urlSessionTask === task }) {
            return existing
        }
        
        let carrier = SnagCarrier(task: task)
        
        if let url = task.originalRequest?.url,
           (url.host == "localhost" || url.host == "127.0.0.1") {
            // Skip Metro bundle/local dev server body data to avoid hangs/circular dependencies
            carrier.shouldSkipBody = true
        }
        
        self.carriers.append(carrier)
        return carrier
    }
    
    private func carrier(with connection: NSURLConnection) -> SnagCarrier? {
        if let existing = self.carriers.first(where: { $0.urlConnection === connection }) {
            return existing
        }
        
        let carrier = SnagCarrier(urlConnection: connection)
        
        if let url = connection.originalRequest.url,
           (url.host == "localhost" || url.host == "127.0.0.1") {
            // Skip Metro bundle/local dev server body data to avoid hangs/circular dependencies
            carrier.shouldSkipBody = true
        }
        
        self.carriers.append(carrier)
        return carrier
    }
    
    // MARK: - SnagSessionInjectorDelegate
    
    func sessionInjector(_ injector: SnagSessionInjector, didStart dataTask: URLSessionTask) {
        performBlock {
            guard let carrier = self.carrier(with: dataTask) else { return }
            if !carrier.hasSentInitialPacket {
                self.send(carrier: carrier)
                carrier.hasSentInitialPacket = true
            }
        }
    }
    
    func sessionInjector(_ injector: SnagSessionInjector, didReceiveResponse dataTask: URLSessionTask, response: URLResponse) {
        performBlock {
            guard let carrier = self.carrier(with: dataTask) else { return }
            if !carrier.hasSentInitialPacket {
                self.send(carrier: carrier)
                carrier.hasSentInitialPacket = true
            }
            carrier.response = response
            self.send(carrier: carrier)
        }
    }
    
    func sessionInjector(_ injector: SnagSessionInjector, didReceiveData dataTask: URLSessionTask, data: Data) {
        let copiedData = Data(data)
        performBlock {
            guard let carrier = self.carrier(with: dataTask) else { return }
            carrier.append(data: copiedData)
        }
    }
    
    func sessionInjector(_ injector: SnagSessionInjector, didFinishWithError dataTask: URLSessionTask, error: Error?) {
        performBlock {
            guard let carrier = self.carrier(with: dataTask) else { return }
            carrier.error = error
            carrier.complete()
            
            self.send(carrier: carrier)
            
            if let index = self.carriers.firstIndex(where: { $0 === carrier }) {
                self.carriers.remove(at: index)
            }
        }
    }
    
    // MARK: - SnagConnectionInjectorDelegate
    
    func connectionInjector(_ injector: SnagConnectionInjector, didStart urlConnection: NSURLConnection) {
        performBlock {
            guard let carrier = self.carrier(with: urlConnection) else { return }
            if !carrier.hasSentInitialPacket {
                self.send(carrier: carrier)
                carrier.hasSentInitialPacket = true
            }
        }
    }
    
    func connectionInjector(_ injector: SnagConnectionInjector, didReceiveResponse urlConnection: NSURLConnection, response: URLResponse) {
        performBlock {
            guard let carrier = self.carrier(with: urlConnection) else { return }
            if !carrier.hasSentInitialPacket {
                self.send(carrier: carrier)
                carrier.hasSentInitialPacket = true
            }
            carrier.response = response
            self.send(carrier: carrier)
        }
    }
    
    func connectionInjector(_ injector: SnagConnectionInjector, didReceiveData urlConnection: NSURLConnection, data: Data) {
        let copiedData = Data(data)
        performBlock {
            guard let carrier = self.carrier(with: urlConnection) else { return }
            carrier.append(data: copiedData)
        }
    }
    
    func connectionInjector(_ injector: SnagConnectionInjector, didFailWithError urlConnection: NSURLConnection, error: Error) {
        performBlock {
            guard let carrier = self.carrier(with: urlConnection) else { return }
            carrier.error = error
            carrier.complete()
            
            self.send(carrier: carrier)
            if let index = self.carriers.firstIndex(where: { $0 === carrier }) {
                self.carriers.remove(at: index)
            }
        }
    }
    
    func connectionInjector(_ injector: SnagConnectionInjector, didFinishLoading urlConnection: NSURLConnection) {
        performBlock {
            guard let carrier = self.carrier(with: urlConnection) else { return }
            carrier.complete()
            
            self.send(carrier: carrier)
            if let index = self.carriers.firstIndex(where: { $0 === carrier }) {
                self.carriers.remove(at: index)
            }
        }
    }
    
    // MARK: - Sending
    
    func send(carrier: SnagCarrier) {
        var packet = carrier.packet()
        packet.project = self.configuration.project
        packet.device = self.configuration.device
        
        if let delegate = self.configuration.carrierDelegate {
            if let modified = delegate.snagCarrierWillSendRequest(packet) {
                packet = modified
            } else {
                return
            }
        }
        
        self.browser.send(packet: packet)
    }
    
    func send(log: SnagLog) {
        let packet = SnagPacket(
            id: UUID().uuidString,
            requestInfo: nil,
            project: self.configuration.project,
            device: self.configuration.device,
            log: log
        )
        self.browser.send(packet: packet)
    }
    
    // MARK: - Handshake & Control
    
    private func sendHandshakePackets() {
        self.sendAppInfo()
        self.browser.send(packet: SnagPacket(control: SnagControl(type: "logStreamingStatusRequest")))
    }
    
    private func sendAppInfo() {
        let appInfo = SnagAppInfo(
            bundleId: Bundle.main.bundleIdentifier,
            isReactNative: NSClassFromString("RCTBridge") != nil
        )
        let control = SnagControl(type: "appInfoResponse", appInfo: appInfo)
        let packet = SnagPacket(control: control)
        self.browser.send(packet: packet)
    }
    
    private func handleReceivedPacket(_ packet: SnagPacket) {
        if let control = packet.control {
            self.handleControl(control)
        }
    }
    
    private func handleControl(_ control: SnagControl) {
        switch control.type {
        case "appInfoRequest":
            self.sendAppInfo()
        case "logStreamingControl":
            if let shouldStream = control.shouldStreamLogs {
                if #available(iOS 15.0, *) {
                    Task {
                        if shouldStream {
                            await SnagLogInterceptor.shared.startCapturing()
                        } else {
                            await SnagLogInterceptor.shared.stopCapturing()
                        }
                    }
                }
            }
        default:
            break
        }
    }
}

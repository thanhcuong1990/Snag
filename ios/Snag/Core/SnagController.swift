import Foundation

class SnagController: SnagSessionInjectorDelegate, SnagConnectionInjectorDelegate {

    var configuration: SnagConfiguration
    var browser: SnagBrowser

    var sessionInjector: SnagSessionInjector?
    var connectionInjector: SnagConnectionInjector?

    private var carriersByTask: [ObjectIdentifier: SnagCarrier] = [:]
    private var carriersByConnection: [ObjectIdentifier: SnagCarrier] = [:]

    private let carrierIdleTimeout: TimeInterval = 600
    private var lastCarrierGC: Date = Date()

    private lazy var cachedAppInfo: SnagAppInfo = SnagAppInfo(
        bundleId: Bundle.main.bundleIdentifier,
        isReactNative: NSClassFromString("RCTBridge") != nil
    )

    let queue = DispatchQueue(label: "com.snag.injectController")

    init(configuration: SnagConfiguration) {
        self.configuration = configuration
        self.browser = SnagBrowser(configuration: configuration)

        self.sessionInjector = SnagSessionInjector(delegate: self)
        // self.connectionInjector = SnagConnectionInjector(delegate: self)

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
        // Ensure we are using the latest metadata which might have been updated in the background
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

    private func makeCarrier(task: URLSessionTask) -> SnagCarrier {
        let carrier = SnagCarrier(task: task)
        carrier.maxBodyBytes = self.configuration.maxBodyCaptureBytes
        if let url = task.originalRequest?.url,
           (url.host == "localhost" || url.host == "127.0.0.1") {
            // Skip Metro bundle/local dev server body data to avoid hangs/circular dependencies
            carrier.shouldSkipBody = true
        }
        return carrier
    }

    private func makeCarrier(connection: NSURLConnection) -> SnagCarrier {
        let carrier = SnagCarrier(urlConnection: connection)
        carrier.maxBodyBytes = self.configuration.maxBodyCaptureBytes
        if let url = connection.originalRequest.url,
           (url.host == "localhost" || url.host == "127.0.0.1") {
            // Skip Metro bundle/local dev server body data to avoid hangs/circular dependencies
            carrier.shouldSkipBody = true
        }
        return carrier
    }

    private func carrier(with task: URLSessionTask) -> SnagCarrier? {
        let key = ObjectIdentifier(task)
        if let existing = self.carriersByTask[key] {
            existing.touch()
            return existing
        }
        let carrier = makeCarrier(task: task)
        self.carriersByTask[key] = carrier
        gcStaleCarriersIfNeeded()
        return carrier
    }

    private func carrier(with connection: NSURLConnection) -> SnagCarrier? {
        let key = ObjectIdentifier(connection)
        if let existing = self.carriersByConnection[key] {
            existing.touch()
            return existing
        }
        let carrier = makeCarrier(connection: connection)
        self.carriersByConnection[key] = carrier
        gcStaleCarriersIfNeeded()
        return carrier
    }

    private func gcStaleCarriersIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastCarrierGC) > 60 else { return }
        lastCarrierGC = now
        let cutoff = now.addingTimeInterval(-carrierIdleTimeout)
        carriersByTask = carriersByTask.filter { _, carrier in
            carrier.lastTouched >= cutoff && carrier.urlSessionTask != nil
        }
        carriersByConnection = carriersByConnection.filter { _, carrier in
            carrier.lastTouched >= cutoff && carrier.urlConnection != nil
        }
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
        performBlock {
            guard let carrier = self.carrier(with: dataTask) else { return }
            carrier.append(data: data)
        }
    }

    func sessionInjector(_ injector: SnagSessionInjector, didFinishWithError dataTask: URLSessionTask, error: Error?) {
        performBlock {
            guard let carrier = self.carrier(with: dataTask) else { return }
            carrier.error = error
            carrier.complete()

            self.send(carrier: carrier)

            self.carriersByTask.removeValue(forKey: ObjectIdentifier(dataTask))
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
        performBlock {
            guard let carrier = self.carrier(with: urlConnection) else { return }
            carrier.append(data: data)
        }
    }

    func connectionInjector(_ injector: SnagConnectionInjector, didFailWithError urlConnection: NSURLConnection, error: Error) {
        performBlock {
            guard let carrier = self.carrier(with: urlConnection) else { return }
            carrier.error = error
            carrier.complete()

            self.send(carrier: carrier)
            self.carriersByConnection.removeValue(forKey: ObjectIdentifier(urlConnection))
        }
    }

    func connectionInjector(_ injector: SnagConnectionInjector, didFinishLoading urlConnection: NSURLConnection) {
        performBlock {
            guard let carrier = self.carrier(with: urlConnection) else { return }
            carrier.complete()

            self.send(carrier: carrier)
            self.carriersByConnection.removeValue(forKey: ObjectIdentifier(urlConnection))
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
        let control = SnagControl(type: "appInfoResponse", appInfo: cachedAppInfo)
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

    func metricsSnapshot() -> SnagMetrics {
        let queueSnapshot = browser.queueMetricsSnapshot()
        let trustSnapshot = SnagTrustStore.shared.metricsSnapshot()

        return SnagMetrics(
            preAuthQueue: SnagQueueMetrics(
                queuedPackets: queueSnapshot.queuedPackets,
                droppedPackets: queueSnapshot.droppedPackets,
                enqueuedPackets: queueSnapshot.enqueuedPackets
            ),
            trust: SnagTrustMetrics(
                trustedServerCount: trustSnapshot.trustedServerCount,
                mismatchCount: trustSnapshot.mismatchCount
            )
        )
    }
}

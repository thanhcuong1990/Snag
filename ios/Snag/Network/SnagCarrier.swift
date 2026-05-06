import Foundation

class SnagCarrier {
    let id: String

    weak var urlSessionTask: URLSessionTask?
    weak var urlConnection: NSURLConnection?

    var response: URLResponse?

    var startDate: Date?
    var endDate: Date?

    var data: Data?
    var error: Error?

    var isCompleted: Bool = false
    var hasSentInitialPacket: Bool = false
    var shouldSkipBody: Bool = false

    var maxBodyBytes: Int = 1_048_576
    var responseBodyTruncated: Bool = false

    var lastTouched: Date = Date()

    var capturedURL: URL?
    var capturedRequestMethod: String?
    var capturedRequestHeaders: [String: String]?
    var capturedRequestBody: Data?
    var capturedRequestBodyTruncated: Bool = false

    init(task: URLSessionTask) {
        self.id = SnagUtility.uuid()
        self.urlSessionTask = task
        self.setup()
        self.refreshRequestSnapshot()
    }

    init(urlConnection: NSURLConnection) {
        self.id = SnagUtility.uuid()
        self.urlConnection = urlConnection
        self.setup()
        self.captureRequest(from: urlConnection.originalRequest)
    }

    var didCaptureRequest: Bool {
        return self.capturedURL != nil || self.capturedRequestMethod != nil
    }

    func refreshRequestSnapshot() {
        if let task = self.urlSessionTask {
            self.captureRequest(from: task.currentRequest ?? task.originalRequest)
        }
    }

    private func captureRequest(from request: URLRequest?) {
        guard let request = request else { return }
        if let url = request.url { self.capturedURL = url }
        if let method = request.httpMethod { self.capturedRequestMethod = method }
        if self.capturedRequestHeaders == nil, let headers = request.allHTTPHeaderFields {
            self.capturedRequestHeaders = headers
        }
        if self.capturedRequestBody == nil, let body = request.httpBody {
            let (cappedBody, wasTruncated) = cappedRequestBody(body)
            self.capturedRequestBody = cappedBody
            self.capturedRequestBodyTruncated = wasTruncated
        }
    }

    private func setup() {
        self.startDate = Date()
        self.data = nil
        self.isCompleted = false
        self.lastTouched = Date()
    }

    func touch() {
        self.lastTouched = Date()
    }

    func append(data: Data) {
        if self.shouldSkipBody { return }
        if self.responseBodyTruncated { return }

        self.lastTouched = Date()

        let currentCount = self.data?.count ?? 0
        let remaining = self.maxBodyBytes - currentCount
        if remaining <= 0 {
            self.responseBodyTruncated = true
            return
        }

        if data.count <= remaining {
            if self.data == nil {
                var initial = Data()
                initial.reserveCapacity(self.expectedCapacity(currentlyAccumulated: 0, incoming: data.count))
                initial.append(data)
                self.data = initial
            } else {
                self.data?.append(data)
            }
        } else {
            if self.data == nil {
                var initial = Data()
                initial.reserveCapacity(remaining)
                initial.append(data.prefix(remaining))
                self.data = initial
            } else {
                self.data?.append(data.prefix(remaining))
            }
            self.responseBodyTruncated = true
        }
    }

    private func expectedCapacity(currentlyAccumulated: Int, incoming: Int) -> Int {
        if let length = expectedContentLength(), length > 0 {
            return min(length, self.maxBodyBytes)
        }
        return min(currentlyAccumulated + incoming, self.maxBodyBytes)
    }

    private func expectedContentLength() -> Int? {
        if let response = self.response as? HTTPURLResponse {
            return Int(response.expectedContentLength)
        }
        if let task = self.urlSessionTask, let response = task.response as? HTTPURLResponse {
            return Int(response.expectedContentLength)
        }
        return nil
    }

    func complete() {
        self.endDate = Date()
        self.isCompleted = true
        self.lastTouched = Date()
    }

    func packet() -> SnagPacket {
        var packet = SnagPacket()
        packet.id = self.id

        var requestInfo = SnagRequestInfo()

        requestInfo.url = self.capturedURL
        requestInfo.requestHeaders = self.capturedRequestHeaders
        requestInfo.requestBody = self.capturedRequestBody
        requestInfo.requestMethod = self.capturedRequestMethod
        if self.capturedRequestBodyTruncated { requestInfo.requestBodyTruncated = true }

        var httpResponse: HTTPURLResponse?

        if let response = self.response as? HTTPURLResponse {
            httpResponse = response
        } else if let task = self.urlSessionTask, let response = task.response as? HTTPURLResponse {
            httpResponse = response
            self.response = response
        }

        if let httpResponse = httpResponse {
            requestInfo.responseHeaders = httpResponse.allHeaderFields as? [String: String]
            requestInfo.statusCode = String(httpResponse.statusCode)
        } else if self.error != nil {
            requestInfo.statusCode = "ERR"
        } else {
            requestInfo.statusCode = "---"
        }

        if self.isCompleted && !self.shouldSkipBody {
            requestInfo.responseData = self.data
            if self.responseBodyTruncated { requestInfo.responseBodyTruncated = true }
        }

        if self.shouldSkipBody {
            requestInfo.requestBody = nil
            requestInfo.responseData = nil
            requestInfo.requestBodyTruncated = nil
            requestInfo.responseBodyTruncated = nil
        }

        requestInfo.startDate = self.startDate
        requestInfo.endDate = self.endDate

        packet.requestInfo = requestInfo

        return packet
    }

    private func cappedRequestBody(_ body: Data?) -> (Data?, Bool) {
        guard let body = body else { return (nil, false) }
        if body.count <= self.maxBodyBytes { return (body, false) }
        return (body.prefix(self.maxBodyBytes), true)
    }
}

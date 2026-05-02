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

    init(task: URLSessionTask) {
        self.id = SnagUtility.uuid()
        self.urlSessionTask = task
        self.setup()
    }

    init(urlConnection: NSURLConnection) {
        self.id = SnagUtility.uuid()
        self.urlConnection = urlConnection
        self.setup()
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

        if let task = self.urlSessionTask {
            requestInfo.url = task.originalRequest?.url
            requestInfo.requestHeaders = task.originalRequest?.allHTTPHeaderFields
            let (body, truncated) = cappedRequestBody(task.originalRequest?.httpBody)
            requestInfo.requestBody = body
            if truncated { requestInfo.requestBodyTruncated = true }
            requestInfo.requestMethod = task.originalRequest?.httpMethod
        } else if let connection = self.urlConnection {
            requestInfo.url = connection.originalRequest.url
            requestInfo.requestHeaders = connection.originalRequest.allHTTPHeaderFields
            let (body, truncated) = cappedRequestBody(connection.originalRequest.httpBody)
            requestInfo.requestBody = body
            if truncated { requestInfo.requestBodyTruncated = true }
            requestInfo.requestMethod = connection.originalRequest.httpMethod
        }

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

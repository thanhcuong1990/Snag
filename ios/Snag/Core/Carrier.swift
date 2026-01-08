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
    }
    
    func append(data: Data) {
        if self.shouldSkipBody { return }
        if self.data == nil {
            self.data = Data(data)
        } else {
            self.data?.append(data)
        }
    }
    
    func complete() {
        self.endDate = Date()
        self.isCompleted = true
    }
    
    func packet() -> SnagPacket {
        var packet = SnagPacket()
        packet.id = self.id
        
        var requestInfo = SnagRequestInfo()
        
        if let task = self.urlSessionTask {
            requestInfo.url = task.originalRequest?.url
            requestInfo.requestHeaders = task.originalRequest?.allHTTPHeaderFields
            requestInfo.requestBody = task.originalRequest?.httpBody
            requestInfo.requestMethod = task.originalRequest?.httpMethod
        } else if let connection = self.urlConnection {
            requestInfo.url = connection.originalRequest.url
            requestInfo.requestHeaders = connection.originalRequest.allHTTPHeaderFields
            requestInfo.requestBody = connection.originalRequest.httpBody
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
        }
        
        if self.shouldSkipBody {
            requestInfo.requestBody = nil
            requestInfo.responseData = nil
        }
        
        requestInfo.startDate = self.startDate
        requestInfo.endDate = self.endDate
        
        packet.requestInfo = requestInfo
        
        return packet
    }
}

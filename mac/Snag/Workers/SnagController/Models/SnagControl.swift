import Cocoa

struct SnagControl: Codable {
    var type: String // "appInfoRequest", "appInfoResponse", "logStreamingControl", "logStreamingStatusRequest", "logStreamingStatusResponse"
    var appInfo: SnagAppInfo?
    var shouldStreamLogs: Bool?
}

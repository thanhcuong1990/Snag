import Cocoa

class CURLRepresentation: ContentRepresentation  {

    @MainActor
    init(curlString: String) {
        super.init()
        self.rawString = curlString
    }

    @MainActor
    init(requestInfo: SnagRequestInfo?) {

        super.init()

        if let requestInfo = requestInfo {
            self.rawString = requestInfo.toCurlCommand(pretty: true) ?? ""
        }
    }
}


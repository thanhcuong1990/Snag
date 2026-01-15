import Cocoa

class CURLRepresentation: ContentRepresentation  {

    init(requestInfo: SnagRequestInfo?) {

        super.init()

        if let requestInfo = requestInfo {
            self.rawString = requestInfo.toCurlCommand(pretty: true) ?? ""
        }
    }
}


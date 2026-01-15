import Foundation

extension SnagPacket {
    func toCurlCommand(pretty: Bool = false) -> String? {
        return self.requestInfo?.toCurlCommand(pretty: pretty)
    }
}

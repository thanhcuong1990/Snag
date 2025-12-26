public protocol SnagCarrierDelegate: AnyObject {
    func snagCarrierWillSendRequest(_ request: SnagPacket) -> SnagPacket?
}

public extension SnagCarrierDelegate {
    func snagCarrierWillSendRequest(_ request: SnagPacket) -> SnagPacket? {
        return request
    }
}

import Foundation

@objcMembers public final class SnagQueueMetrics: NSObject {
    public let queuedPackets: Int
    public let droppedPackets: Int
    public let enqueuedPackets: Int

    init(queuedPackets: Int, droppedPackets: Int, enqueuedPackets: Int) {
        self.queuedPackets = queuedPackets
        self.droppedPackets = droppedPackets
        self.enqueuedPackets = enqueuedPackets
    }
}

@objcMembers public final class SnagTrustMetrics: NSObject {
    public let trustedServerCount: Int
    public let mismatchCount: Int

    init(trustedServerCount: Int, mismatchCount: Int) {
        self.trustedServerCount = trustedServerCount
        self.mismatchCount = mismatchCount
    }
}

@objcMembers public final class SnagMetrics: NSObject {
    public let preAuthQueue: SnagQueueMetrics
    public let trust: SnagTrustMetrics

    init(preAuthQueue: SnagQueueMetrics, trust: SnagTrustMetrics) {
        self.preAuthQueue = preAuthQueue
        self.trust = trust
    }
}

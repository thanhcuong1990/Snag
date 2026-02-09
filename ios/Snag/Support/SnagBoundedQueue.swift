import Foundation

struct SnagQueueMetricsSnapshot {
    let queuedPackets: Int
    let droppedPackets: Int
    let enqueuedPackets: Int
}

final class SnagBoundedQueue<Element> {
    private let maxSize: Int
    private var items: [Element] = []
    private var droppedCount: Int = 0
    private var enqueuedCount: Int = 0

    init(maxSize: Int) {
        self.maxSize = max(1, maxSize)
    }

    @discardableResult
    func enqueue(_ item: Element) -> Bool {
        enqueuedCount += 1
        var dropped = false
        if items.count >= maxSize {
            items.removeFirst()
            droppedCount += 1
            dropped = true
        }
        items.append(item)
        return dropped
    }

    func drain() -> [Element] {
        let drained = items
        items.removeAll()
        return drained
    }

    func clear() {
        items.removeAll()
    }

    func snapshot() -> SnagQueueMetricsSnapshot {
        return SnagQueueMetricsSnapshot(
            queuedPackets: items.count,
            droppedPackets: droppedCount,
            enqueuedPackets: enqueuedCount
        )
    }
}

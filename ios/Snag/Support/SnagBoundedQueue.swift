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
    private let lock = NSLock()

    init(maxSize: Int) {
        self.maxSize = max(1, maxSize)
    }

    @discardableResult
    func enqueue(_ item: Element) -> Bool {
        lock.lock(); defer { lock.unlock() }
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
        lock.lock(); defer { lock.unlock() }
        let drained = items
        items.removeAll()
        return drained
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        items.removeAll()
    }

    func snapshot() -> SnagQueueMetricsSnapshot {
        lock.lock(); defer { lock.unlock() }
        return SnagQueueMetricsSnapshot(
            queuedPackets: items.count,
            droppedPackets: droppedCount,
            enqueuedPackets: enqueuedCount
        )
    }
}

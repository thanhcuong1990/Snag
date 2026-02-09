import XCTest
@testable import Snag

final class SnagBoundedQueueTests: XCTestCase {
    func testDropOldestWhenQueueIsFull() {
        let queue = SnagBoundedQueue<Int>(maxSize: 2)

        XCTAssertFalse(queue.enqueue(1))
        XCTAssertFalse(queue.enqueue(2))
        XCTAssertTrue(queue.enqueue(3))

        let drained = queue.drain()
        XCTAssertEqual(drained, [2, 3])

        let snapshot = queue.snapshot()
        XCTAssertEqual(snapshot.queuedPackets, 0)
        XCTAssertEqual(snapshot.droppedPackets, 1)
        XCTAssertEqual(snapshot.enqueuedPackets, 3)
    }
}

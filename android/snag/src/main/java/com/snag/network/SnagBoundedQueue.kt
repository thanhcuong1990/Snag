package com.snag.network

internal data class SnagBoundedQueueSnapshot(
    val size: Int,
    val droppedCount: Long,
    val enqueuedCount: Long
)

internal data class SnagBoundedQueueEnqueueResult(
    val dropped: Boolean,
    val size: Int,
    val droppedCount: Long
)

internal class SnagBoundedQueue<T>(private val maxSize: Int) {
    private val queue = ArrayDeque<T>()
    private var droppedCount: Long = 0
    private var enqueuedCount: Long = 0

    init {
        require(maxSize > 0) { "maxSize must be greater than zero" }
    }

    @Synchronized
    fun enqueue(item: T): SnagBoundedQueueEnqueueResult {
        enqueuedCount += 1
        var dropped = false
        if (queue.size >= maxSize) {
            queue.removeFirst()
            droppedCount += 1
            dropped = true
        }
        queue.addLast(item)
        return SnagBoundedQueueEnqueueResult(
            dropped = dropped,
            size = queue.size,
            droppedCount = droppedCount
        )
    }

    @Synchronized
    fun drain(): List<T> {
        val drained = queue.toList()
        queue.clear()
        return drained
    }

    @Synchronized
    fun size(): Int = queue.size

    @Synchronized
    fun snapshot(): SnagBoundedQueueSnapshot {
        return SnagBoundedQueueSnapshot(
            size = queue.size,
            droppedCount = droppedCount,
            enqueuedCount = enqueuedCount
        )
    }
}

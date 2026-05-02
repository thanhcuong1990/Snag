package com.snag.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SnagBoundedQueueTest {
    @Test
    fun dropsOldestWhenFull() {
        val queue = SnagBoundedQueue<Int>(maxSize = 2)

        assertEquals(false, queue.enqueue(1).dropped)
        assertEquals(false, queue.enqueue(2).dropped)
        val overflow = queue.enqueue(3)
        assertEquals(true, overflow.dropped)
        assertEquals(2, overflow.size)
        assertEquals(1, overflow.droppedCount)

        val drained = queue.drain()
        assertEquals(listOf(2, 3), drained)

        val snapshot = queue.snapshot()
        assertEquals(0, snapshot.size)
        assertEquals(1, snapshot.droppedCount)
        assertEquals(3, snapshot.enqueuedCount)
    }

    @Test
    fun enforcesPositiveMaxSize() {
        try {
            SnagBoundedQueue<Int>(maxSize = 0)
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message?.contains("maxSize") == true)
            return
        }
        throw AssertionError("Expected IllegalArgumentException")
    }
}

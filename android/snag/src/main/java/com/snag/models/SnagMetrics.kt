package com.snag.models

data class SnagQueueMetrics(
    val queuedPackets: Int,
    val droppedPackets: Long,
    val enqueuedPackets: Long
)

data class SnagTrustMetrics(
    val trustedServerCount: Int,
    val mismatchCount: Long
)

data class SnagMetrics(
    val preAuthQueue: SnagQueueMetrics,
    val transportQueue: SnagQueueMetrics,
    val trust: SnagTrustMetrics
)

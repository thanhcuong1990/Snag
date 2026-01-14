package com.snag.core.network

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Utility for framing/deframing packets with an 8-byte little-endian length prefix.
 */
internal object PacketFraming {
    const val HEADER_SIZE = 8
    const val MAX_BODY_SIZE = 50_000_000 // 50MB safety limit

    /**
     * Wraps payload with 8-byte length header.
     */
    fun frame(payload: ByteArray): ByteArray {
        return ByteBuffer.allocate(HEADER_SIZE + payload.size)
            .order(ByteOrder.LITTLE_ENDIAN)
            .putLong(payload.size.toLong())
            .put(payload)
            .array()
    }

    /**
     * Extracts length from an 8-byte header buffer.
     */
    fun parseLength(header: ByteArray): Int {
        val length = ByteBuffer.wrap(header)
            .order(ByteOrder.LITTLE_ENDIAN)
            .long.toInt()
        
        if (length < 0 || length > MAX_BODY_SIZE) {
            throw IllegalArgumentException("Invalid packet length: $length")
        }
        return length
    }
}

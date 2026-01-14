package com.snag.core.browser

import com.snag.models.RequestInfo

interface Browser {
    fun sendPacket(requestInfo: RequestInfo)
    fun sendPacket(requestInfo: RequestInfo, packetId: String)
    fun sendLog(log: com.snag.models.SnagLog)
    fun sendPacket(packet: com.snag.models.Packet)

    fun interface PacketListener {
        fun onPacketReceived(packet: com.snag.models.Packet)
    }
    fun addPacketListener(listener: PacketListener)
    fun removePacketListener(listener: PacketListener)

    companion object {
        private var instance: Browser? = null

        internal fun initialize(instance: Browser) {
            this.instance = instance
        }

        fun getInstance(): Browser = instance ?: throw IllegalStateException("Snag is not started")

        fun isInitialized(): Boolean = instance != null
    }
}

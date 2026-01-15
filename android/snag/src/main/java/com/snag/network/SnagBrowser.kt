package com.snag.network

import com.snag.models.SnagRequestInfo
import com.snag.models.SnagPacket
import com.snag.models.SnagLog

interface SnagBrowser {
    fun sendPacket(requestInfo: SnagRequestInfo)
    fun sendPacket(requestInfo: SnagRequestInfo, packetId: String)
    fun sendLog(log: SnagLog)
    fun sendPacket(packet: SnagPacket)

    fun interface PacketListener {
        fun onPacketReceived(packet: SnagPacket)
    }
    fun addPacketListener(listener: PacketListener)
    fun removePacketListener(listener: PacketListener)

    companion object {
        private var instance: SnagBrowser? = null

        internal fun initialize(instance: SnagBrowser) {
            this.instance = instance
        }

        fun getInstance(): SnagBrowser = instance ?: throw IllegalStateException("Snag is not started")

        fun isInitialized(): Boolean = instance != null
    }
}

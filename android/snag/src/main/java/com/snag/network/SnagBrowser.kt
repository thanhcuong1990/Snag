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
        private val noOpInstance by lazy { NoOpSnagBrowser() }

        internal fun initialize(instance: SnagBrowser) {
            this.instance = instance
        }

        fun getInstance(): SnagBrowser = instance ?: noOpInstance

        fun isInitialized(): Boolean = instance != null
    }
}

private class NoOpSnagBrowser : SnagBrowser {
    override fun sendPacket(requestInfo: SnagRequestInfo) {}
    override fun sendPacket(requestInfo: SnagRequestInfo, packetId: String) {}
    override fun sendLog(log: SnagLog) {}
    override fun sendPacket(packet: SnagPacket) {}
    override fun addPacketListener(listener: SnagBrowser.PacketListener) {}
    override fun removePacketListener(listener: SnagBrowser.PacketListener) {}
}


package com.snag.core.browser

import com.snag.models.RequestInfo

interface Browser {
    fun sendPacket(requestInfo: RequestInfo)
    fun sendPacket(requestInfo: RequestInfo, packetId: String)
    fun sendLog(log: com.snag.models.SnagLog)

    companion object {
        private var instance: Browser? = null

        internal fun initialize(instance: Browser) {
            this.instance = instance
        }

        fun getInstance(): Browser = instance ?: throw IllegalStateException("Snag is not started")

        fun isInitialized(): Boolean = instance != null
    }
}

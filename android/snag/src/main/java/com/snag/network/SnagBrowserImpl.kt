package com.snag.network

import android.content.Context
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import com.snag.core.SnagConfiguration
import com.snag.discovery.DiscoveryManager
import com.snag.models.SnagDevice
import com.snag.models.SnagPacket
import com.snag.models.SnagProject
import com.snag.models.SnagRequestInfo
import com.snag.models.SnagLog
import com.snag.models.SnagMetrics
import com.snag.models.SnagQueueMetrics
import com.snag.core.log.SnagInternalLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.util.concurrent.ConcurrentHashMap

internal class SnagBrowserImpl(
    private val context: Context,
    private val config: SnagConfiguration
) : SnagBrowser, DiscoveryManager.DiscoveryListener {

    private val snagScope = MainScope()

    private var project: SnagProject? = null
    private var device: SnagDevice? = null

    private val json by lazy {
        Json {
            prettyPrint = false
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }

    private val packetListeners = java.util.concurrent.CopyOnWriteArrayList<SnagBrowser.PacketListener>()
    
    private val connectionManager = ConnectionManager(
        context = context,
        scope = snagScope,
        json = json,
        onPacketReceived = { serviceName, packet ->
            if (handleHandshakePacket(serviceName = serviceName, packet = packet)) {
                // Handled
            } else {
                packetListeners.forEach { it.onPacketReceived(packet) }
            }
        }
    ).apply {
        setConfig(config)
    }

    private val serviceAuthModes = ConcurrentHashMap<String, String>()

    private val discoveryManager = DiscoveryManager(
        context = context,
        config = config,
        listener = this
    )

    private var multicastLock: WifiManager.MulticastLock? = null
    
    private val pendingPackets = SnagBoundedQueue<SnagPacket>(maxSize = MAX_PENDING_PACKETS)
    private var lastPendingDropWarningCount: Long = 0

    fun start(project: SnagProject, device: SnagDevice) {
        this.project = project
        this.device = device
        
        // Acquire multicast lock for NSD discovery
        try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifiManager?.createMulticastLock("SnagMulticastLock")?.apply {
                setReferenceCounted(true)
                acquire()
            }
        } catch (e: Exception) {
            SnagInternalLogger.e(e, "Snag: Failed to acquire multicast lock")
        }

        // Start discovery
        discoveryManager.startDiscovery()

        // Optional debug host connection
        config.debugHost?.let { host ->
            snagScope.launch(Dispatchers.IO) {
                connectionManager.connectToHost(host, config.debugPort, "DebugHost") {
                    clearServiceAuth("DebugHost")
                    sendHelloPacket("DebugHost")
                }
            }
        }
    }


    override fun onServiceFound(serviceInfo: NsdServiceInfo) {
        val address = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            serviceInfo.hostAddresses.firstOrNull()
        } else {
            @Suppress("DEPRECATION")
            serviceInfo.host
        }

        address?.hostAddress?.let { hostAddress ->
            connectionManager.connectToHost(hostAddress, serviceInfo.port, serviceInfo.serviceName) {
                clearServiceAuth(serviceInfo.serviceName)
                sendHelloPacket(serviceInfo.serviceName)
            }
        }
    }

    override fun onServiceLost(serviceInfo: NsdServiceInfo) {
        clearServiceAuth(serviceInfo.serviceName)
        connectionManager.disconnectService(serviceInfo.serviceName)
    }

    private fun sendHelloPacket(serviceName: String) {
        val proj = project ?: return
        val dev = device ?: return
        val helloControl = com.snag.models.SnagControl(type = "hello", deviceId = dev.deviceId)
        val packet = SnagPacket(control = helloControl, device = dev, project = proj)
        connectionManager.send(packet, preferredServiceName = normalizeServiceName(serviceName))
    }

    override fun sendPacket(requestInfo: SnagRequestInfo) {
        sendPacket(requestInfo, java.util.UUID.randomUUID().toString())
    }

    override fun sendPacket(requestInfo: SnagRequestInfo, packetId: String) {
        val proj = project
        val dev = device
        
        val packet = SnagPacket(
            id = packetId,
            requestInfo = requestInfo,
            project = proj,
            device = dev
        )
        
        if (proj == null || dev == null || (config.isSecurityEnabled && !hasAuthenticatedService())) {
            enqueuePendingPacket(packet, reason = "request_info_not_ready")
        } else {
            sendEncryptedIfRequired(packet)
        }
    }

    override fun sendLog(log: SnagLog) {
        val proj = project
        val dev = device
        
        val packet = SnagPacket(
            project = proj,
            device = dev,
            log = log
        )
        
        if (proj == null || dev == null || (config.isSecurityEnabled && !hasAuthenticatedService())) {
            enqueuePendingPacket(packet, reason = "log_not_ready")
        } else {
            sendEncryptedIfRequired(packet)
        }
    }

    override fun sendPacket(packet: SnagPacket) {
         val proj = project
         val dev = device
         
         val type = packet.control?.type
         val isHandshake = type == "hello"

         if (isHandshake) {
             connectionManager.send(packet, preferredServiceName = null)
             return
         }

         if (proj == null || dev == null || (config.isSecurityEnabled && !hasAuthenticatedService())) {
             enqueuePendingPacket(packet, reason = "packet_not_ready")
         } else {
             sendEncryptedIfRequired(packet)
         }
    }

    override fun addPacketListener(listener: SnagBrowser.PacketListener) {
        packetListeners.add(listener)
    }

    override fun removePacketListener(listener: SnagBrowser.PacketListener) {
        packetListeners.remove(listener)
    }
    // MARK: - Handshake

    private fun handleHandshakePacket(serviceName: String, packet: SnagPacket): Boolean {
        val type = packet.control?.type ?: return false
        
        if (type == "auth_success") {
            val normalizedService = normalizeServiceName(serviceName)
            val authMode = packet.control.authMode ?: "cleartext"
            serviceAuthModes[normalizedService] = authMode
            SnagInternalLogger.d("Auth Success. service=%s mode=%s", normalizedService, authMode)
            flushPendingPackets()
            return true
        }
        
        return false
    }

    private fun sendEncryptedIfRequired(packet: SnagPacket) {
        val preferredServiceName = if (config.isSecurityEnabled) {
            firstAuthenticatedService()
        } else {
            null
        }

        if (config.isSecurityEnabled && preferredServiceName == null) {
            enqueuePendingPacket(packet, reason = "no_authenticated_service")
            return
        }

        connectionManager.send(packet, preferredServiceName = preferredServiceName)
    }

    private fun enqueuePendingPacket(packet: SnagPacket, reason: String) {
        val dropped = pendingPackets.enqueue(packet)
        val snapshot = pendingPackets.snapshot()
        if (dropped) {
            val shouldLogDrop = synchronized(this) {
                val droppedCount = snapshot.droppedCount
                val shouldLog = droppedCount == 1L || droppedCount - lastPendingDropWarningCount >= DROP_WARNING_LOG_INTERVAL
                if (shouldLog) {
                    lastPendingDropWarningCount = droppedCount
                }
                shouldLog
            }

            if (shouldLogDrop) {
                SnagInternalLogger.w(
                    "Pending packet queue full (%d). Dropping oldest packet. dropped=%d reason=%s",
                    MAX_PENDING_PACKETS,
                    snapshot.droppedCount,
                    reason
                )
            }
        }
        if (snapshot.size == MAX_PENDING_PACKETS || snapshot.size % 50 == 0) {
            SnagInternalLogger.d(
                "Pending packet queue size=%d dropped=%d reason=%s",
                snapshot.size,
                snapshot.droppedCount,
                reason
            )
        }
    }

    private fun flushPendingPackets() {
        val pendingToFlush = pendingPackets.drain()

        if (pendingToFlush.isNotEmpty()) {
            val snapshot = pendingPackets.snapshot()
            SnagInternalLogger.d(
                "Flushing %d pending packets (dropped=%d)",
                pendingToFlush.size,
                snapshot.droppedCount
            )
        }

        pendingToFlush.forEach { packet ->
            val enrichedPacket = packet.copy(project = project, device = device)
            sendEncryptedIfRequired(enrichedPacket)
        }
    }

    private fun hasAuthenticatedService(): Boolean {
        return serviceAuthModes.isNotEmpty()
    }

    private fun firstAuthenticatedService(): String? {
        val iterator = serviceAuthModes.keys.iterator()
        while (iterator.hasNext()) {
            val serviceName = iterator.next()
            if (connectionManager.hasActiveConnection(serviceName)) {
                return serviceName
            }
            serviceAuthModes.remove(serviceName)
        }
        return null
    }

    private fun clearServiceAuth(serviceName: String) {
        serviceAuthModes.remove(normalizeServiceName(serviceName))
    }

    private fun normalizeServiceName(serviceName: String): String {
        return serviceName.lowercase()
    }

    internal fun metricsSnapshot() = SnagMetrics(
        preAuthQueue = pendingPackets.snapshot().toExportedMetrics(),
        transportQueue = connectionManager.transportQueueMetricsSnapshot(),
        trust = connectionManager.trustMetricsSnapshot()
    )

    companion object {
        private const val MAX_PENDING_PACKETS = 500
        private const val DROP_WARNING_LOG_INTERVAL = 100L
    }

    private fun SnagBoundedQueueSnapshot.toExportedMetrics(): SnagQueueMetrics {
        return SnagQueueMetrics(
            queuedPackets = size,
            droppedPackets = droppedCount,
            enqueuedPackets = enqueuedCount
        )
    }
}

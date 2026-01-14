package com.snag.core.browser

import android.content.Context
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import com.snag.core.config.Config
import com.snag.core.discovery.DiscoveryManager
import com.snag.core.network.ConnectionManager
import com.snag.models.Device
import com.snag.models.Packet
import com.snag.models.Project
import com.snag.models.RequestInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import timber.log.Timber

internal class BrowserImpl(
    private val context: Context,
    private val config: Config,
    private val project: Project,
    private val device: Device
) : Browser, DiscoveryManager.DiscoveryListener {

    private val snagScope = MainScope()

    private val json by lazy {
        Json {
            prettyPrint = false
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }

    private val packetListeners = java.util.concurrent.CopyOnWriteArrayList<Browser.PacketListener>()
    
    private val connectionManager = ConnectionManager(
        scope = snagScope,
        json = json,
        onPacketReceived = { packet ->
            packetListeners.forEach { it.onPacketReceived(packet) }
        }
    )

    private val discoveryManager = DiscoveryManager(
        context = context,
        config = config,
        listener = this
    )

    private var multicastLock: WifiManager.MulticastLock? = null

    init {
        start()
    }

    private fun start() {
        // Acquire multicast lock for NSD discovery
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("SnagMulticastLock").apply {
            setReferenceCounted(true)
            acquire()
        }

        // Start discovery
        discoveryManager.startDiscovery()

        // Optional debug host connection
        config.debugHost?.let { host ->
            snagScope.launch(Dispatchers.IO) {
                connectionManager.connectToHost(host, config.debugPort, "DebugHost") {
                    sendHelloPacket()
                }
            }
        }
    }

    override fun onServiceFound(serviceInfo: NsdServiceInfo) {
        val addresses = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            serviceInfo.hostAddresses
        } else {
            @Suppress("DEPRECATION")
            listOf(serviceInfo.host)
        }

        addresses.forEach { address ->
            address.hostAddress?.let { hostAddress ->
                connectionManager.connectToHost(hostAddress, serviceInfo.port, serviceInfo.serviceName) {
                    sendHelloPacket()
                }
            }
        }
    }

    override fun onServiceLost(serviceInfo: NsdServiceInfo) {
        connectionManager.disconnectService(serviceInfo.serviceName)
    }

    private fun sendHelloPacket() {
        sendPacket(Packet(device = device, project = project))
    }

    override fun sendPacket(requestInfo: RequestInfo) {
        sendPacket(requestInfo, java.util.UUID.randomUUID().toString())
    }

    override fun sendPacket(requestInfo: RequestInfo, packetId: String) {
        sendPacket(
            Packet(
                packetId = packetId,
                requestInfo = requestInfo,
                project = project,
                device = device
            )
        )
    }

    override fun sendLog(log: com.snag.models.SnagLog) {
        sendPacket(
            Packet(
                project = project,
                device = device,
                log = log
            )
        )
    }

    override fun sendPacket(packet: Packet) {
        connectionManager.send(packet)
    }

    override fun addPacketListener(listener: Browser.PacketListener) {
        packetListeners.add(listener)
    }

    override fun removePacketListener(listener: Browser.PacketListener) {
        packetListeners.remove(listener)
    }
}

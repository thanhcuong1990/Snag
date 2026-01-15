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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import timber.log.Timber

internal class SnagBrowserImpl(
    private val context: Context,
    private val config: SnagConfiguration,
    private val project: SnagProject,
    private val device: SnagDevice
) : SnagBrowser, DiscoveryManager.DiscoveryListener {

    private val snagScope = MainScope()

    private val json by lazy {
        Json {
            prettyPrint = false
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }

    private val packetListeners = java.util.concurrent.CopyOnWriteArrayList<SnagBrowser.PacketListener>()
    
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
        sendPacket(SnagPacket(device = device, project = project))
    }

    override fun sendPacket(requestInfo: SnagRequestInfo) {
        sendPacket(requestInfo, java.util.UUID.randomUUID().toString())
    }

    override fun sendPacket(requestInfo: SnagRequestInfo, packetId: String) {
        sendPacket(
            SnagPacket(
                id = packetId,
                requestInfo = requestInfo,
                project = project,
                device = device
            )
        )
    }

    override fun sendLog(log: SnagLog) {
        sendPacket(
            SnagPacket(
                project = project,
                device = device,
                log = log
            )
        )
    }

    override fun sendPacket(packet: SnagPacket) {
        connectionManager.send(packet)
    }

    override fun addPacketListener(listener: SnagBrowser.PacketListener) {
        packetListeners.add(listener)
    }

    override fun removePacketListener(listener: SnagBrowser.PacketListener) {
        packetListeners.remove(listener)
    }
}

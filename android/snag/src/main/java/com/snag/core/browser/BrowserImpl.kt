package com.snag.core.browser

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import androidx.annotation.RequiresApi
import com.snag.core.config.Config
import com.snag.core.discovery.NsdDiscoveryListener
import com.snag.core.discovery.NsdResolveListener
import com.snag.core.discovery.NsdServiceInfoCallback
import com.snag.models.Device
import com.snag.models.Packet
import com.snag.models.Project
import com.snag.models.RequestInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import timber.log.Timber
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue

internal class BrowserImpl(
    private val context: Context,
    private val config: Config,
    private val project: Project,
    private val device: Device
) : Browser {

    private val snagScope = MainScope()

    private val json by lazy {
        Json {
            prettyPrint = false
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }

    private val nsdManager by lazy {
        context.getSystemService(Context.NSD_SERVICE) as NsdManager
    }

    private val discoverExecutor by lazy { Executors.newSingleThreadExecutor() }

    private val nsdServices = ConcurrentHashMap<String, NsdServiceInfo>()
    private val socketConnections = ConcurrentHashMap<String, MutableMap<String, Socket>>()
    
    // Memory-safe buffers
    private val packetChannel = Channel<Packet>(
        capacity = MAX_PACKET_BUFFER,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    private val pendingBuffers = LinkedBlockingQueue<ByteArray>(MAX_OFFLINE_BUFFER)

    private var multicastLock: WifiManager.MulticastLock? = null

    private val nsdServiceInfoCallback
        get() = @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
        object : NsdServiceInfoCallback {
            private var nsdServiceInfo: NsdServiceInfo? = null

            override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                nsdServiceInfo = serviceInfo
                onNsdServiceInfoFound(serviceInfo)
            }

            override fun onServiceLost() {
                val serviceInfo = nsdServiceInfo ?: return
                onNsdServiceLost(serviceInfo)
            }
        }

    private val nsdResolveListener
        get() = object : NsdResolveListener {
            private var nsdServiceInfo: NsdServiceInfo? = null

            override fun onServiceResolved(serviceInfo: NsdServiceInfo?) {
                val nsdInfo = nsdServiceInfo
                if (serviceInfo == null && nsdInfo != null) {
                    nsdServices.remove(nsdInfo.serviceName)
                    return
                }
                serviceInfo ?: return
                nsdServiceInfo = serviceInfo
                onNsdServiceInfoFound(serviceInfo)
            }
        }

    private val nsdDiscoveryListener = object : NsdDiscoveryListener {
        override fun onServiceFound(serviceInfo: NsdServiceInfo?) {
            serviceInfo ?: return

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                nsdManager.registerServiceInfoCallback(
                    serviceInfo,
                    Executors.newSingleThreadExecutor(),
                    nsdServiceInfoCallback
                )
            } else {
                nsdManager.resolveService(
                    serviceInfo,
                    nsdResolveListener
                )
            }
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo?) {
            serviceInfo ?: return
            onNsdServiceLost(serviceInfo)
        }
    }

    private fun sendHelloPacket() {
        send(Packet(device = device, project = project))
    }

    override fun sendPacket(requestInfo: RequestInfo, packetId: String) {
        send(
            Packet(
                packetId = packetId,
                requestInfo = requestInfo,
                project = project,
                device = device
            )
        )
    }

    private fun send(packet: Packet) {
        // Instant, non-blocking send to background processing channel
        packetChannel.trySend(packet)
    }

    private fun processPacket(packet: Packet) {
        val payload = try {
            json.encodeToString(packet).toByteArray()
        } catch (e: Exception) {
            Timber.e(e, "Failed to encode packet")
            return
        }

        val buffer = ByteBuffer.allocate(8 + payload.size)
            .order(ByteOrder.LITTLE_ENDIAN)
            .apply {
                putLong(payload.size.toLong())
                put(payload)
            }

        val data = buffer.array()
        val targets = socketConnections.entries.flatMap { serviceEntry ->
            serviceEntry.value.entries.map { hostEntry ->
                Triple(serviceEntry.key, hostEntry.key, hostEntry.value)
            }
        }

        if (targets.isEmpty()) {
            pendingBuffers.offer(data)
            attemptReconnect()
            return
        }

        snagScope.launch(Dispatchers.IO) {
            val succeeded = targets.map { (serviceName, hostAddress, socket) ->
                async {
                    try {
                        if (!socket.isClosed) {
                            synchronized(socket) {
                                socket.getOutputStream().write(data)
                            }
                            true
                        } else {
                            false
                        }
                    } catch (_: Exception) {
                        try {
                            socket.close()
                        } catch (_: Exception) {
                        }
                        socketConnections[serviceName]?.remove(hostAddress)
                        false
                    }
                }
            }.awaitAll().any { it }

            if (!succeeded) {
                pendingBuffers.offer(data)
                attemptReconnect()
            }
        }
    }

    override fun sendPacket(requestInfo: RequestInfo) {
        sendPacket(requestInfo = requestInfo, packetId = java.util.UUID.randomUUID().toString())
    }

    override fun sendLog(log: com.snag.models.SnagLog) {
        send(
            Packet(
                project = project,
                device = device,
                log = log
            )
        )
    }

    init {
        start()
        startPacketConsumer()
    }

    private fun startPacketConsumer() {
        snagScope.launch(Dispatchers.IO) {
            for (packet in packetChannel) {
                processPacket(packet)
            }
        }
    }

    private fun start() {
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("SnagMulticastLock").apply {
            setReferenceCounted(true)
            acquire()
        }

        config.debugHost?.let { host ->
            snagScope.launch(Dispatchers.IO) {
                connectToHost(host, config.debugPort, "DebugHost")
            }
        }

        with(nsdManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                discoverServices(
                    config.netServiceType,
                    NsdManager.PROTOCOL_DNS_SD,
                    null,
                    discoverExecutor,
                    nsdDiscoveryListener
                )
            } else {
                discoverServices(
                    config.netServiceType,
                    NsdManager.PROTOCOL_DNS_SD,
                    nsdDiscoveryListener
                )
            }
        }
    }

    private fun onNsdServiceInfoFound(nsdServiceInfo: NsdServiceInfo) {
        snagScope.launch(Dispatchers.IO) {
            val serviceName = nsdServiceInfo.serviceName
            nsdServices[serviceName] = nsdServiceInfo

            val addresses = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                nsdServiceInfo.hostAddresses
            } else {
                listOf(nsdServiceInfo.host)
            }

            addresses.forEach { address ->
                address.hostAddress?.let { hostAddress ->
                    connectToHost(hostAddress, nsdServiceInfo.port, serviceName)
                }
            }
        }
    }

    private fun connectToHost(hostAddress: String, port: Int, serviceName: String) {
        val connections = socketConnections.getOrPut(serviceName) { mutableMapOf() }
        
        val existing = connections[hostAddress]
        if (existing != null) {
            if (!existing.isConnected || existing.isClosed) {
                connections.remove(hostAddress)
            } else {
                return
            }
        }

        try {
            Timber.d("Connecting to $hostAddress:$port")
            val socket = Socket().apply {
                keepAlive = true
                connect(InetSocketAddress(hostAddress, port), 1500)
            }

            if (socket.isConnected) {
                Timber.d("Connected with $hostAddress:$port hostname: $serviceName")
                connections[hostAddress] = socket
                flushPending()
                sendHelloPacket()
            }
        } catch (e: Exception) {
            Timber.w("Connection failed to $hostAddress:$port: ${e.message}")
        }
    }

    private fun flushPending() {
        val targets = socketConnections.entries.flatMap { serviceEntry ->
            serviceEntry.value.entries.map { hostEntry ->
                Triple(serviceEntry.key, hostEntry.key, hostEntry.value)
            }
        }
        if (targets.isEmpty()) return

        snagScope.launch(Dispatchers.IO) {
            while (true) {
                val payload = pendingBuffers.poll() ?: break
                val succeeded = targets.map { (serviceName, hostAddress, socket) ->
                    async {
                        try {
                            if (!socket.isClosed) {
                                synchronized(socket) {
                                    socket.getOutputStream().write(payload)
                                }
                                true
                            } else {
                                false
                            }
                        } catch (_: Exception) {
                            try {
                                socket.close()
                            } catch (_: Exception) {
                            }
                            socketConnections[serviceName]?.remove(hostAddress)
                            false
                        }
                    }
                }.awaitAll().any { it }

                if (!succeeded) {
                    pendingBuffers.offer(payload)
                    attemptReconnect()
                    break
                }
            }
        }
    }

    private fun attemptReconnect() {
        config.debugHost?.let { host ->
            snagScope.launch(Dispatchers.IO) {
                connectToHost(host, config.debugPort, "DebugHost")
            }
        }

        nsdServices.entries.forEach { entry ->
            val serviceName = entry.key
            val serviceInfo = entry.value
            val port = serviceInfo.port

            val addresses = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                serviceInfo.hostAddresses
            } else {
                listOf(serviceInfo.host)
            }

            addresses.forEach { address ->
                address.hostAddress?.let { hostAddress ->
                    snagScope.launch(Dispatchers.IO) {
                        connectToHost(hostAddress, port, serviceName)
                    }
                }
            }
        }
    }

    private fun onNsdServiceLost(nsdServiceInfo: NsdServiceInfo) {
        val serviceName = nsdServiceInfo.serviceName
        socketConnections.remove(serviceName)?.values?.forEach { socket ->
            if (socket.isConnected) socket.close()
        }
        nsdServices.remove(serviceName)
    }

    companion object {
        private const val MAX_PACKET_BUFFER = 500
        private const val MAX_OFFLINE_BUFFER = 50
    }
}

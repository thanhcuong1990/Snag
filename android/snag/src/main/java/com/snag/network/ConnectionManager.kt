package com.snag.network

import com.snag.models.SnagPacket
import com.snag.models.SnagControl
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import timber.log.Timber
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import java.security.cert.X509Certificate

/**
 * Manages active socket connections, packet serialization, and delivery.
 */
internal class ConnectionManager(
    private val scope: CoroutineScope,
    private val json: Json,
    private val onPacketReceived: (SnagPacket) -> Unit
) {
    private val socketConnections = ConcurrentHashMap<String, MutableMap<String, Socket>>()
    private val pendingBuffers = LinkedBlockingQueue<ByteArray>(MAX_OFFLINE_BUFFER)
    private val lastReconnectAttempt = AtomicLong(0)

    // Packet ingestion channel
    private val packetChannel = Channel<SnagPacket>(
        capacity = MAX_PACKET_BUFFER,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )

    private var config: com.snag.core.SnagConfiguration? = null

    fun setConfig(config: com.snag.core.SnagConfiguration) {
        this.config = config
    }

    init {
        scope.launch(Dispatchers.IO) {
            for (packet in packetChannel) {
                processPacket(packet)
            }
        }
    }

    fun send(packet: SnagPacket) {
        packetChannel.trySend(packet)
    }

    fun connectToHost(hostAddress: String, port: Int, serviceName: String, onConnected: () -> Unit = {}) {
        val connections = socketConnections.getOrPut(serviceName) { mutableMapOf() }
        
        synchronized(connections) {
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
                
                val socket = if (config?.isSecurityEnabled == true) {
                    createSSLSocket(hostAddress, port)
                } else {
                    Socket().apply {
                        connect(InetSocketAddress(hostAddress, port), 1500)
                    }
                }
                
                socket.apply {
                    keepAlive = true
                }

                if (socket.isConnected) {
                    Timber.d("Connected to $serviceName at $hostAddress:$port")
                    connections[hostAddress] = socket
                    
                    if (config?.isSecurityEnabled == true) {
                        sendAuthPacket(socket)
                    }
                    
                    startReceiving(socket)
                    onConnected()
                    flushPending()
                }
            } catch (e: Exception) {
                Timber.w("Connection failed to $hostAddress:$port: ${e.message}")
            }
        }
    }

    fun disconnectService(serviceName: String) {
        socketConnections.remove(serviceName)?.values?.forEach { socket ->
            try {
                if (socket.isConnected) socket.close()
            } catch (e: Exception) {
                Timber.w("Error closing socket: ${e.message}")
            }
        }
    }

    private fun processPacket(packet: SnagPacket) {
        val payload = try {
            json.encodeToString(packet).toByteArray()
        } catch (e: Exception) {
            Timber.e(e, "Failed to encode packet")
            return
        }

        val data = PacketFraming.frame(payload)
        
        val firstTarget = getFirstAvailableTarget()
        if (firstTarget == null) {
            pendingBuffers.offer(data)
            return
        }

        val (serviceName, hostAddress, socket) = firstTarget
        val succeeded = writeToSocket(socket, data, serviceName, hostAddress)

        if (!succeeded) {
            pendingBuffers.offer(data)
        }
    }

    private fun getFirstAvailableTarget(): Triple<String, String, Socket>? {
        return socketConnections.entries.firstNotNullOfOrNull { serviceEntry ->
            serviceEntry.value.entries.firstOrNull()?.let { hostEntry ->
                Triple(serviceEntry.key, hostEntry.key, hostEntry.value)
            }
        }
    }

    private fun writeToSocket(socket: Socket, data: ByteArray, serviceName: String, hostAddress: String): Boolean {
        return try {
            if (!socket.isClosed) {
                synchronized(socket) {
                    socket.getOutputStream().write(data)
                }
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Timber.w("Write failed to $hostAddress: ${e.message}")
            closeSocketSilently(socket, serviceName, hostAddress)
            false
        }
    }

    private fun closeSocketSilently(socket: Socket, serviceName: String, hostAddress: String) {
        try {
            socket.close()
        } catch (_: Exception) {}
        socketConnections[serviceName]?.remove(hostAddress)
    }

    private fun flushPending() {
        val targets = socketConnections.entries.flatMap { serviceEntry ->
            serviceEntry.value.entries.map { hostEntry ->
                Triple(serviceEntry.key, hostEntry.key, hostEntry.value)
            }
        }
        if (targets.isEmpty()) return

        scope.launch(Dispatchers.IO) {
            while (true) {
                val payload = pendingBuffers.poll() ?: break
                val succeeded = targets.any { (serviceName, hostAddress, socket) ->
                    writeToSocket(socket, payload, serviceName, hostAddress)
                }

                if (!succeeded) {
                    pendingBuffers.offer(payload)
                    break
                }
            }
        }
    }

    private fun startReceiving(socket: Socket) {
        scope.launch(Dispatchers.IO) {
            val inputStream = socket.getInputStream()
            val headerBuffer = ByteArray(PacketFraming.HEADER_SIZE)
            
            while (!socket.isClosed && socket.isConnected) {
                try {
                    if (!readFully(inputStream, headerBuffer)) break
                    
                    val length = PacketFraming.parseLength(headerBuffer)
                    val bodyBuffer = ByteArray(length)
                    
                    if (!readFully(inputStream, bodyBuffer)) break
                    
                    val packetString = String(bodyBuffer)
                    try {
                        val packet = json.decodeFromString<SnagPacket>(packetString)
                        withContext(Dispatchers.Main) {
                            onPacketReceived(packet)
                        }
                    } catch (e: Exception) {
                        Timber.e(e, "Snag: Failed to decode packet: $packetString")
                    }
                } catch (e: Exception) {
                    Timber.w("Receive error: ${e.message}")
                    break
                }
            }
        }
    }

    private fun readFully(inputStream: java.io.InputStream, buffer: ByteArray): Boolean {
        var read = 0
        while (read < buffer.size) {
            val r = inputStream.read(buffer, read, buffer.size - read)
            if (r == -1) return false
            read += r
        }
        return true
    }

    fun shouldAttemptReconnect(): Boolean {
        val now = System.currentTimeMillis()
        val last = lastReconnectAttempt.get()
        if (now - last < RECONNECT_THROTTLE_MS) return false
        return lastReconnectAttempt.compareAndSet(last, now)
    }

    private fun sendAuthPacket(socket: Socket) {
        val currentConfig = config ?: return
        val authControl = SnagControl(type = "authPIN", authPIN = currentConfig.securityPIN)
        
        // Use SnagAppMetadataProvider to ensure consistent Project and Device info
        // This prevents "duplicate" devices appearing on the Mac app (one from auth, one from handshake)
        val context = com.snag.Snag.appContext
        
        val project = if (context != null) {
            com.snag.core.SnagAppMetadataProvider.getProject(context, currentConfig.projectName)
        } else {
            com.snag.models.SnagProject(projectName = currentConfig.projectName)
        }

        val device = if (context != null) {
            com.snag.core.SnagAppMetadataProvider.getDevice(context)
        } else {
            // Fallback if context is somehow null (unlikely if Snag.start() was called)
             com.snag.models.SnagDevice(
                deviceName = "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}",
                deviceId = java.util.UUID.randomUUID().toString()
            )
        }
        
        val authPacket = SnagPacket(
            control = authControl,
            project = project,
            device = device
        )
        
        try {
            val payload = json.encodeToString(authPacket).toByteArray()
            val data = PacketFraming.frame(payload)
            socket.getOutputStream().write(data)
            socket.getOutputStream().flush()
        } catch (e: Exception) {
            Timber.e(e, "Snag: Failed to send auth packet")
        }
    }

    @android.annotation.SuppressLint("CustomX509TrustManager")
    private fun createSSLSocket(host: String, port: Int): Socket {
        val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })

        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, trustAllCerts, java.security.SecureRandom())
        val factory = sslContext.socketFactory
        val socket = factory.createSocket() as SSLSocket
        socket.connect(InetSocketAddress(host, port), 1500)
        socket.startHandshake()
        return socket
    }

    companion object {
        private const val MAX_PACKET_BUFFER = 500
        private const val MAX_OFFLINE_BUFFER = 50
        private const val RECONNECT_THROTTLE_MS = 2000L
    }
}

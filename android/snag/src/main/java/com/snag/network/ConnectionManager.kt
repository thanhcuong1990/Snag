package com.snag.network

import android.content.Context
import com.snag.core.SnagIdentityMismatchEvent
import com.snag.core.log.SnagInternalLogger
import com.snag.models.SnagPacket
import com.snag.models.SnagQueueMetrics
import com.snag.models.SnagTrustMetrics
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
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
    context: Context,
    private val scope: CoroutineScope,
    private val json: Json,
    private val onPacketReceived: (serviceName: String, packet: SnagPacket) -> Unit
) {
    private val socketConnections = ConcurrentHashMap<String, ConcurrentHashMap<String, Socket>>()
    private val pendingBuffers = LinkedBlockingQueue<PendingBuffer>(MAX_OFFLINE_BUFFER)
    private val lastReconnectAttempt = AtomicLong(0)
    private val enqueuedPendingBuffers = AtomicLong(0)
    private val droppedPendingBuffers = AtomicLong(0)

    // Packet ingestion channel
    private val packetChannel = Channel<OutboundPacket>(
        capacity = MAX_PACKET_BUFFER,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    private val trustStore = SnagTrustStore.getInstance(context)

    private var config: com.snag.core.SnagConfiguration? = null

    fun setConfig(config: com.snag.core.SnagConfiguration) {
        this.config = config
    }

    init {
        scope.launch(Dispatchers.IO) {
            for (outbound in packetChannel) {
                try {
                    processPacket(outbound)
                } catch (e: Exception) {
                    SnagInternalLogger.e(e, "Snag: Error processing packet in IO loop")
                }
            }
        }
    }

    fun send(packet: SnagPacket, preferredServiceName: String? = null) {
        packetChannel.trySend(OutboundPacket(packet = packet, preferredServiceName = preferredServiceName?.lowercase()))
    }

    fun connectToHost(hostAddress: String, port: Int, serviceName: String, onConnected: () -> Unit = {}) {
        val normalizedServiceName = serviceName.lowercase()
        val connections = socketConnections.getOrPut(normalizedServiceName) { ConcurrentHashMap() }
        
        var shouldTriggerConnected = false
        synchronized(connections) {
            // If we already have any active connection for this service, don't create another one.
            // This prevents the handshake race condition where multiple interfaces (WiFi, Ethernet, etc.)
            // connect simultaneously and challenges/responses get mixed up.
            val activeConnection = connections.values.firstOrNull { it.isConnected && !it.isClosed }
            if (activeConnection != null) {
                SnagInternalLogger.d("Already connected to service %s. Skipping %s.", normalizedServiceName, hostAddress)
                return
            }

            try {
                SnagInternalLogger.d("Connecting to $hostAddress:$port")
                
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
                    val trustKey = trustKeyFor(serviceName = normalizedServiceName, hostAddress = hostAddress, port = port)
                    if (!validateServerTrust(socket = socket, trustKey = trustKey)) {
                        closeSocketSilently(socket, normalizedServiceName, hostAddress)
                        return
                    }

                    SnagInternalLogger.d("Connected to %s at %s:%d", normalizedServiceName, hostAddress, port)
                    connections[hostAddress] = socket
                    
                    startReceiving(socket = socket, serviceName = normalizedServiceName, hostAddress = hostAddress)
                    shouldTriggerConnected = true
                }
            } catch (e: Exception) {
                SnagInternalLogger.w("Connection failed to $hostAddress:$port: ${e.message}")
            }
        }
        
        if (shouldTriggerConnected) {
            onConnected()
            flushPending()
        }
    }

    fun disconnectService(serviceName: String) {
        socketConnections.remove(serviceName.lowercase())?.values?.forEach { socket ->
            try {
                if (socket.isConnected) socket.close()
            } catch (e: Exception) {
                SnagInternalLogger.w("Error closing socket: ${e.message}")
            }
        }
    }

    fun hasActiveConnection(serviceName: String): Boolean {
        val normalized = serviceName.lowercase()
        val serviceConnections = socketConnections[normalized] ?: return false
        return serviceConnections.values.any { socket -> socket.isConnected && !socket.isClosed }
    }

    private fun processPacket(outbound: OutboundPacket) {
        val payload = try {
            json.encodeToString(outbound.packet).toByteArray()
        } catch (e: Exception) {
            SnagInternalLogger.e(e, "Failed to encode packet")
            return
        }

        val data = PacketFraming.frame(payload)

        val target = getAvailableTarget(preferredServiceName = outbound.preferredServiceName)
        if (target == null) {
            enqueuePendingBuffer(PendingBuffer(data = data, preferredServiceName = outbound.preferredServiceName))
            return
        }

        val (serviceName, hostAddress, socket) = target
        val succeeded = writeToSocket(socket, data, serviceName, hostAddress)

        if (!succeeded) {
            enqueuePendingBuffer(PendingBuffer(data = data, preferredServiceName = outbound.preferredServiceName))
        }
    }

    private fun getAvailableTarget(preferredServiceName: String?): Triple<String, String, Socket>? {
        if (preferredServiceName != null) {
            val preferredTargets = socketConnections[preferredServiceName] ?: return null
            return preferredTargets.entries.firstOrNull()?.let { hostEntry ->
                Triple(preferredServiceName, hostEntry.key, hostEntry.value)
            }
        }

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
                    val outputStream = socket.getOutputStream()
                    outputStream.write(data)
                    outputStream.flush()
                }
                true
            } else {
                false
            }
        } catch (e: Exception) {
            SnagInternalLogger.w("Write failed to $hostAddress: ${e.message}")
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

    private fun trustKeyFor(serviceName: String, hostAddress: String, port: Int): String {
        if (serviceName.equals("DebugHost", ignoreCase = true)) {
            return "debug|${hostAddress.lowercase()}:$port"
        }
        return "bonjour|${serviceName.lowercase()}"
    }

    private fun validateServerTrust(socket: Socket, trustKey: String): Boolean {
        if (socket !is SSLSocket) return true

        return try {
            val cert = socket.session.peerCertificates.firstOrNull() as? X509Certificate
            if (cert == null) {
                SnagInternalLogger.e("TLS peer certificate is missing for key=%s", trustKey)
                false
            } else {
                val fingerprint = sha256Hex(cert.encoded)
                when (val decision = trustStore.verifyOrTrust(trustKey, fingerprint)) {
                    is SnagTrustDecision.Trusted -> true
                    is SnagTrustDecision.Mismatch -> {
                        notifyIdentityMismatch(
                            trustKey = trustKey,
                            expected = decision.expectedFingerprint,
                            actual = decision.actualFingerprint
                        )
                        false
                    }
                }
            }
        } catch (e: Exception) {
            SnagInternalLogger.e(e, "Failed to validate TLS trust for key=%s", trustKey)
            false
        }
    }

    private fun sha256Hex(input: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input)
        return digest.joinToString(separator = "") { byte -> "%02x".format(byte) }
    }

    private fun flushPending() {
        scope.launch(Dispatchers.IO) {
            val itemsToProcess = pendingBuffers.size
            repeat(itemsToProcess) {
                val pending = pendingBuffers.poll() ?: return@repeat
                val targets = targetsForPending(preferredServiceName = pending.preferredServiceName)
                if (targets.isEmpty()) {
                    enqueuePendingBuffer(pending)
                    return@repeat
                }

                val succeeded = targets.any { (serviceName, hostAddress, socket) ->
                    writeToSocket(socket, pending.data, serviceName, hostAddress)
                }

                if (!succeeded) {
                    enqueuePendingBuffer(pending)
                }
            }
        }
    }

    private fun enqueuePendingBuffer(buffer: PendingBuffer) {
        enqueuedPendingBuffers.incrementAndGet()
        val offered = pendingBuffers.offer(buffer)
        if (!offered) {
            droppedPendingBuffers.incrementAndGet()
            SnagInternalLogger.w("Transport queue full (%d). Dropping packet.", MAX_OFFLINE_BUFFER)
        }
    }

    private fun targetsForPending(preferredServiceName: String?): List<Triple<String, String, Socket>> {
        if (preferredServiceName != null) {
            val preferredTargets = socketConnections[preferredServiceName] ?: return emptyList()
            return preferredTargets.entries.map { hostEntry ->
                Triple(preferredServiceName, hostEntry.key, hostEntry.value)
            }
        }
        return socketConnections.entries.flatMap { serviceEntry ->
            serviceEntry.value.entries.map { hostEntry ->
                Triple(serviceEntry.key, hostEntry.key, hostEntry.value)
            }
        }
    }

    private fun startReceiving(socket: Socket, serviceName: String, hostAddress: String) {
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
                            onPacketReceived(serviceName, packet)
                        }
                    } catch (e: Exception) {
                        SnagInternalLogger.e(e, "Snag: Failed to decode packet: $packetString")
                    }
                } catch (e: Exception) {
                    SnagInternalLogger.w("Receive error: ${e.message}")
                    break
                }
            }

            closeSocketSilently(socket, serviceName, hostAddress)
        }
    }

    private fun notifyIdentityMismatch(trustKey: String, expected: String, actual: String) {
        val listener = config?.securityListener
        if (listener == null) {
            SnagInternalLogger.e(
                "Snag identity mismatch for key=%s. expected=%s actual=%s. Recovery: Call Snag.resetTrustedServers() after confirming trusted server identity.",
                trustKey,
                expected,
                actual
            )
            return
        }
        scope.launch(Dispatchers.Main) {
            listener.onServerIdentityMismatch(
                SnagIdentityMismatchEvent(
                    serverKey = trustKey,
                    expectedFingerprint = expected,
                    actualFingerprint = actual
                )
            )
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

    fun transportQueueMetricsSnapshot(): SnagQueueMetrics {
        return SnagQueueMetrics(
            queuedPackets = pendingBuffers.size,
            droppedPackets = droppedPendingBuffers.get(),
            enqueuedPackets = enqueuedPendingBuffers.get()
        )
    }

    fun trustMetricsSnapshot(): SnagTrustMetrics {
        return trustStore.metricsSnapshot()
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

    private data class OutboundPacket(
        val packet: SnagPacket,
        val preferredServiceName: String?
    )

    private data class PendingBuffer(
        val data: ByteArray,
        val preferredServiceName: String?
    )
}

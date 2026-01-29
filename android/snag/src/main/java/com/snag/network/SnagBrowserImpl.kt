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
import com.snag.core.SnagCrypto
import com.snag.models.SnagLog
import kotlinx.coroutines.Dispatchers
import java.util.Base64
import javax.crypto.SecretKey
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import timber.log.Timber

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
        scope = snagScope,
        json = json,
        onPacketReceived = { packet ->
            if (handleHandshakePacket(packet)) {
                // Consumed by handshake
            } else if (packet.control?.encryptedPayload != null) {
                // Decrypt
                handleEncryptedPacket(packet)
            } else {
                // Normal packet
                packetListeners.forEach { it.onPacketReceived(packet) }
            }
        }
    ).apply {
        setConfig(config)
    }

    private var sessionKey: SecretKey? = null
    private var authMode: String? = null

    init {
        // Redefine callback wrapper or handle logic here?
        // Since we pass callback in constructor, we can't redefine connectionManager easily.
        // Wait, onPacketReceived is a val? No, it's a lambda.
        // ConnectionManager constructor takes it.
        // We can't change it.
        // But we can check packet types in the existing listener forwarding?
        // Ah, `packetListeners.forEach`.
        // We need to INTERCEPT before listeners.
        // Refactor ConnectionManager construction?
        // Or add this logic to `packetListeners`?
        // If we add it as a listener, we might be too late or race condition?
        // No, listeners are called in order? CopyOnWriteArrayList.
        // But `SnagBrowser` itself implements `PacketListener`? No.
        // ConnectionManager calls `onPacketReceived` -> `packetListeners.forEach`.
        // I should have injected `this::handlePacket` instead of lambda.
    }
    
    // Changing ConnectionManager construction


    private val discoveryManager = DiscoveryManager(
        context = context,
        config = config,
        listener = this
    )

    private var multicastLock: WifiManager.MulticastLock? = null
    
    private val pendingPackets = java.util.Collections.synchronizedList(mutableListOf<SnagPacket>())

    fun start(project: SnagProject, device: SnagDevice) {
        this.project = project
        this.device = device
        
        // Flush pending packets with new metadata
        synchronized(pendingPackets) {
            val iterator = pendingPackets.iterator()
            while (iterator.hasNext()) {
                val packet = iterator.next()
                // Update packet with metadata before sending
                val enrichedPacket = packet.copy(project = project, device = device)
                connectionManager.send(enrichedPacket)
                iterator.remove()
            }
        }
        
        // Acquire multicast lock for NSD discovery
        try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifiManager?.createMulticastLock("SnagMulticastLock")?.apply {
                setReferenceCounted(true)
                acquire()
            }
        } catch (e: Exception) {
            Timber.e(e, "Snag: Failed to acquire multicast lock")
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
        val proj = project ?: return
        val dev = device ?: return
        sendPacket(SnagPacket(device = dev, project = proj))
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
        
        if (proj == null || dev == null || (config.isSecurityEnabled && authMode == null)) {
            pendingPackets.add(packet)
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
        
        if (proj == null || dev == null || (config.isSecurityEnabled && authMode == null)) {
            pendingPackets.add(packet)
        } else {
            sendEncryptedIfRequired(packet)
        }
    }

    override fun sendPacket(packet: SnagPacket) {
         val proj = project
         val dev = device
         
         if (proj == null || dev == null || (config.isSecurityEnabled && authMode == null)) {
             pendingPackets.add(packet)
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
    // MARK: - Handshake & Encryption

    private fun handleHandshakePacket(packet: SnagPacket): Boolean {
        val type = packet.control?.type ?: return false
        
        if (type == "auth_required") {
            val saltHex = packet.control.salt ?: return true
            val pin = config.securityPIN ?: return true
            
            val salt = SnagCrypto.hexToBytes(saltHex)
            val key = SnagCrypto.deriveKey(pin, salt)
            this.sessionKey = key
            
            // Verify
            // Hash(Key + "Client")
            val validation = "Client".toByteArray(Charsets.UTF_8)
            val keyBytes = key.encoded // SecretKeySpec returns encoded.
            // Concatenate
            val dataToHash = keyBytes + validation
            val hashBytes = java.security.MessageDigest.getInstance("SHA-256").digest(dataToHash)
            val hashHex = SnagCrypto.bytesToHex(hashBytes)
            
            val verifyControl = com.snag.models.SnagControl(type = "auth_verify", authHash = hashHex)
            val verifyPacket = SnagPacket(control = verifyControl, project = project, device = device)
            
            connectionManager.send(verifyPacket)
            return true
        } else if (type == "auth_success") {
            this.authMode = packet.control.authMode
            Timber.d("Auth Success. Mode: ${this.authMode}")
            flushPendingPackets()
            return true
        }
        
        return false
    }

    private fun handleEncryptedPacket(packet: SnagPacket) {
        val payloadBase64 = packet.control?.encryptedPayload ?: return
        val nonceBase64 = packet.control?.encryptedNonce ?: return
        val key = this.sessionKey ?: return
        
        try {
            val ciphertext = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                Base64.getDecoder().decode(payloadBase64)
            } else {
                 android.util.Base64.decode(payloadBase64, android.util.Base64.DEFAULT)
            }
            
            val nonce = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                Base64.getDecoder().decode(nonceBase64)
            } else {
                android.util.Base64.decode(nonceBase64, android.util.Base64.DEFAULT)
            }
            
            val plaintext = SnagCrypto.decrypt(ciphertext, nonce, key)
            val jsonString = String(plaintext, Charsets.UTF_8)
            val decryptedPacket = json.decodeFromString<SnagPacket>(jsonString)
            
            packetListeners.forEach { it.onPacketReceived(decryptedPacket) }
        } catch (e: Exception) {
            Timber.e(e, "Decryption failed")
        }
    }

    private fun sendEncryptedIfRequired(packet: SnagPacket) {
        if (authMode == "encrypted") {
            val key = sessionKey
            if (key != null) {
                try {
                    val jsonString = json.encodeToString(packet)
                    val plaintext = jsonString.toByteArray(Charsets.UTF_8)
                    val result = SnagCrypto.encrypt(plaintext, key) // (ciphertext, nonce)
                    
                    val cipherBase64 = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        Base64.getEncoder().encodeToString(result.first)
                    } else {
                        android.util.Base64.encodeToString(result.first, android.util.Base64.NO_WRAP)
                    }
                    
                    val nonceBase64 = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        Base64.getEncoder().encodeToString(result.second)
                    } else {
                         android.util.Base64.encodeToString(result.second, android.util.Base64.NO_WRAP)
                    }
                    
                    val wrapperControl = com.snag.models.SnagControl(
                        type = "data",
                        encryptedPayload = cipherBase64,
                        encryptedNonce = nonceBase64
                    )
                    
                    val wrapperPacket = SnagPacket(
                        control = wrapperControl,
                        device = packet.device, // Header
                        project = packet.project
                    )
                    
                    connectionManager.send(wrapperPacket)
                    return
                } catch (e: Exception) {
                    Timber.e(e, "Encryption failed")
                }
            }
        }
        // Fallback or Cleartext
        connectionManager.send(packet)
    }

    private fun flushPendingPackets() {
         synchronized(pendingPackets) {
            val iterator = pendingPackets.iterator()
            while (iterator.hasNext()) {
                val packet = iterator.next()
                val enrichedPacket = packet.copy(project = project, device = device)
                sendEncryptedIfRequired(enrichedPacket)
                iterator.remove()
            }
        }
    }
}

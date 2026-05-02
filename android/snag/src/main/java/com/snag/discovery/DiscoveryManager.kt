package com.snag.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import androidx.annotation.RequiresApi
import com.snag.core.SnagConfiguration
import com.snag.core.log.SnagInternalLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.Executors

/**
 * Manages Network Service Discovery (NSD) for finding Snag instances.
 */
internal class DiscoveryManager(
    private val context: Context,
    private val config: SnagConfiguration,
    private val listener: DiscoveryListener
) {
    private val nsdManager by lazy {
        context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    }


    private val discoverExecutor = Executors.newSingleThreadExecutor()
    private val retryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    interface DiscoveryListener {
        fun onServiceFound(serviceInfo: NsdServiceInfo)
        fun onServiceLost(serviceInfo: NsdServiceInfo)
    }

    private val nsdDiscoveryListener = object : NsdDiscoveryListener {
        override fun onServiceFound(serviceInfo: NsdServiceInfo?) {
            serviceInfo ?: return
            SnagInternalLogger.d("Service found: ${serviceInfo.serviceName}")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                registerServiceInfoCallback(serviceInfo)
            } else {
                resolveServiceWithRetry(serviceInfo)
            }
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo?) {
            serviceInfo ?: return
            SnagInternalLogger.d("Service lost: ${serviceInfo.serviceName}")
            listener.onServiceLost(serviceInfo)
        }
    }
    
    private fun resolveServiceWithRetry(serviceInfo: NsdServiceInfo, attempt: Int = 0) {
        @Suppress("DEPRECATION")
        nsdManager?.resolveService(serviceInfo, object : NsdResolveListener {
            override fun onServiceResolved(resolvedInfo: NsdServiceInfo?) {
                resolvedInfo ?: return
                SnagInternalLogger.d("Service resolved: ${resolvedInfo.serviceName} at ${resolvedInfo.host}:${resolvedInfo.port}")
                listener.onServiceFound(resolvedInfo)
            }

            override fun onResolveFailed(failedInfo: NsdServiceInfo?, errorCode: Int) {
                SnagInternalLogger.w("Resolve failed for ${failedInfo?.serviceName} with error: $errorCode. Attempt: $attempt")
                
                if (errorCode == NsdManager.FAILURE_ALREADY_ACTIVE) {
                    // Likely a collision; back off briefly and retry without blocking the executor.
                    retryScope.launch {
                        delay(500)
                        resolveServiceWithRetry(serviceInfo, attempt + 1)
                    }
                } else if (attempt < 5) {
                    val backoffMs = (1000L * (attempt + 1))
                    retryScope.launch {
                        delay(backoffMs)
                        resolveServiceWithRetry(serviceInfo, attempt + 1)
                    }
                } else {
                    SnagInternalLogger.w("Service resolution failed after $attempt attempts. Giving up on ${failedInfo?.serviceName}")
                }
            }
        })
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun registerServiceInfoCallback(serviceInfo: NsdServiceInfo) {
        val callback = object : NsdServiceInfoCallback {
            override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                SnagInternalLogger.d("Service updated: ${serviceInfo.serviceName}")
                listener.onServiceFound(serviceInfo)
            }

            override fun onServiceLost() {
                // Handled by discovery listener primarily
            }
        }
        nsdManager?.registerServiceInfoCallback(serviceInfo, discoverExecutor, callback)
    }


    fun startDiscovery() {
        SnagInternalLogger.d("Starting NSD discovery for ${config.netServiceType}")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                nsdManager?.discoverServices(
                    config.netServiceType,
                    NsdManager.PROTOCOL_DNS_SD,
                    null,
                    discoverExecutor,
                    nsdDiscoveryListener
                )
            } else {
                nsdManager?.discoverServices(
                    config.netServiceType,
                    NsdManager.PROTOCOL_DNS_SD,
                    nsdDiscoveryListener
                )
            }
        } catch (e: Exception) {
            SnagInternalLogger.e(e, "Failed to start discovery")
        }
    }

    fun stopDiscovery() {
        SnagInternalLogger.d("Stopping NSD discovery")
        try {
            nsdManager?.stopServiceDiscovery(nsdDiscoveryListener)
        } catch (e: Exception) {
            SnagInternalLogger.e(e, "Failed to stop discovery")
        }
        try {
            retryScope.cancel()
        } catch (_: Exception) { }
    }
}

package com.snag.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import androidx.annotation.RequiresApi
import com.snag.core.SnagConfiguration
import timber.log.Timber
import java.util.concurrent.Executor
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

    interface DiscoveryListener {
        fun onServiceFound(serviceInfo: NsdServiceInfo)
        fun onServiceLost(serviceInfo: NsdServiceInfo)
    }

    private val nsdDiscoveryListener = object : NsdDiscoveryListener {
        override fun onServiceFound(serviceInfo: NsdServiceInfo?) {
            serviceInfo ?: return
            Timber.d("Service found: ${serviceInfo.serviceName}")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                registerServiceInfoCallback(serviceInfo)
            } else {
                resolveServiceWithRetry(serviceInfo)
            }
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo?) {
            serviceInfo ?: return
            Timber.d("Service lost: ${serviceInfo.serviceName}")
            listener.onServiceLost(serviceInfo)
        }
    }
    
    private fun resolveServiceWithRetry(serviceInfo: NsdServiceInfo, attempt: Int = 0) {
        @Suppress("DEPRECATION")
        nsdManager?.resolveService(serviceInfo, object : NsdResolveListener {
            override fun onServiceResolved(resolvedInfo: NsdServiceInfo?) {
                resolvedInfo ?: return
                Timber.d("Service resolved: ${resolvedInfo.serviceName} at ${resolvedInfo.host}:${resolvedInfo.port}")
                listener.onServiceFound(resolvedInfo)
            }

            override fun onResolveFailed(failedInfo: NsdServiceInfo?, errorCode: Int) {
                Timber.w("Resolve failed for ${failedInfo?.serviceName} with error: $errorCode. Attempt: $attempt")
                
                if (errorCode == NsdManager.FAILURE_ALREADY_ACTIVE) {
                    // Just wait a bit and retry, likely collision
                     discoverExecutor.execute {
                        try { Thread.sleep(500) } catch (_: Exception) {}
                        resolveServiceWithRetry(serviceInfo, attempt + 1)
                    }
                } else {
                    // Other failures, retry with backoff up to a limit
                    if (attempt < 5) {
                        discoverExecutor.execute {
                            try { Thread.sleep((1000 * (attempt + 1)).toLong()) } catch (_: Exception) {}
                             resolveServiceWithRetry(serviceInfo, attempt + 1)
                        }
                    } else {
                        Timber.e("Service resolution failed after $attempt attempts. Giving up on ${failedInfo?.serviceName}")
                    }
                }
            }
        })
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun registerServiceInfoCallback(serviceInfo: NsdServiceInfo) {
        val callback = object : NsdServiceInfoCallback {
            override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
                Timber.d("Service updated: ${serviceInfo.serviceName}")
                listener.onServiceFound(serviceInfo)
            }

            override fun onServiceLost() {
                // Handled by discovery listener primarily
            }
        }
        nsdManager?.registerServiceInfoCallback(serviceInfo, discoverExecutor, callback)
    }


    fun startDiscovery() {
        Timber.d("Starting NSD discovery for ${config.netServiceType}")
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
            Timber.e(e, "Failed to start discovery")
        }
    }

    fun stopDiscovery() {
        Timber.d("Stopping NSD discovery")
        try {
            nsdManager?.stopServiceDiscovery(nsdDiscoveryListener)
        } catch (e: Exception) {
            Timber.e(e, "Failed to stop discovery")
        }
    }
}

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
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Manages Network Service Discovery (NSD) for finding Snag instances.
 *
 * Android NSD is unreliable in two well-known ways: (1) `discoverServices` can fail with
 * a transient error at startup (Wi-Fi not yet associated, mdnsd busy, FAILURE_ALREADY_ACTIVE)
 * and the listener will never recover on its own; (2) once running, discovery can go stale
 * and stop noticing late-arriving services. We work around both: retry-with-backoff on
 * start failures and unexpected stops, and a periodic stop+restart to keep discovery fresh.
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

    // Whether the caller wants discovery active. The listener callbacks consult this to
    // decide whether to schedule a restart after an unexpected stop or failure.
    private val isWanted = AtomicBoolean(false)
    private val isRunning = AtomicBoolean(false)
    private var startRetryJob: Job? = null
    private var refreshJob: Job? = null
    private var startAttempt: Int = 0

    interface DiscoveryListener {
        fun onServiceFound(serviceInfo: NsdServiceInfo)
        fun onServiceLost(serviceInfo: NsdServiceInfo)
    }

    private val nsdDiscoveryListener = object : NsdDiscoveryListener {
        override fun onDiscoveryStarted(serviceType: String?) {
            SnagInternalLogger.d("onDiscoveryStarted for $serviceType")
            isRunning.set(true)
            startAttempt = 0
        }

        override fun onDiscoveryStopped(serviceType: String?) {
            SnagInternalLogger.d("onDiscoveryStopped for $serviceType")
            isRunning.set(false)
            // Either we requested a stop (intentional shutdown OR a refresh cycle) or the
            // system stopped it on us. In either case, if discovery is still wanted,
            // kick off a fresh discoverServices call.
            if (isWanted.get()) {
                scheduleStartRetry(immediate = true)
            }
        }

        override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
            SnagInternalLogger.w("onStartDiscoveryFailed for $serviceType errorCode=$errorCode")
            isRunning.set(false)
            // The system may still hold the listener registration; release it before retry.
            try { nsdManager?.stopServiceDiscovery(this) } catch (_: Exception) {}
            if (isWanted.get()) {
                scheduleStartRetry(immediate = false)
            }
        }

        override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {
            SnagInternalLogger.w("onStopDiscoveryFailed for $serviceType errorCode=$errorCode")
        }

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
        // Captured so the listener overrides can use `serviceInfo` (matching the supertype
        // parameter name) without shadowing the outer non-null target.
        val targetInfo = serviceInfo
        @Suppress("DEPRECATION")
        nsdManager?.resolveService(targetInfo, object : NsdResolveListener {
            override fun onServiceResolved(serviceInfo: NsdServiceInfo?) {
                serviceInfo ?: return
                SnagInternalLogger.d("Service resolved: ${serviceInfo.serviceName} at ${serviceInfo.host}:${serviceInfo.port}")
                listener.onServiceFound(serviceInfo)
            }

            override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {
                SnagInternalLogger.w("Resolve failed for ${serviceInfo?.serviceName} with error: $errorCode. Attempt: $attempt")

                if (errorCode == NsdManager.FAILURE_ALREADY_ACTIVE) {
                    // Likely a collision; back off briefly and retry without blocking the executor.
                    retryScope.launch {
                        delay(500)
                        resolveServiceWithRetry(targetInfo, attempt + 1)
                    }
                } else if (attempt < 5) {
                    val backoffMs = (1000L * (attempt + 1))
                    retryScope.launch {
                        delay(backoffMs)
                        resolveServiceWithRetry(targetInfo, attempt + 1)
                    }
                } else {
                    SnagInternalLogger.w("Service resolution failed after $attempt attempts. Giving up on ${serviceInfo?.serviceName}")
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
        if (!isWanted.compareAndSet(false, true)) return
        startAttempt = 0
        invokeDiscoverServices()
        startPeriodicRefresh()
    }

    fun stopDiscovery() {
        if (!isWanted.compareAndSet(true, false)) return
        SnagInternalLogger.d("Stopping NSD discovery")
        startRetryJob?.cancel()
        startRetryJob = null
        refreshJob?.cancel()
        refreshJob = null
        try {
            nsdManager?.stopServiceDiscovery(nsdDiscoveryListener)
        } catch (e: Exception) {
            SnagInternalLogger.e(e, "Failed to stop discovery")
        }
        try {
            retryScope.cancel()
        } catch (_: Exception) { }
    }

    private fun invokeDiscoverServices() {
        if (!isWanted.get()) return
        if (isRunning.get()) return
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
            scheduleStartRetry(immediate = false)
        }
    }

    private fun scheduleStartRetry(immediate: Boolean) {
        if (!isWanted.get()) return
        startRetryJob?.cancel()
        startRetryJob = retryScope.launch {
            val delayMs = if (immediate) {
                250L
            } else {
                val attempt = startAttempt.coerceAtMost(MAX_RETRY_BACKOFF_STEPS)
                startAttempt = attempt + 1
                (1000L shl attempt).coerceAtMost(MAX_RETRY_BACKOFF_MS)
            }
            delay(delayMs)
            if (isWanted.get() && !isRunning.get()) {
                invokeDiscoverServices()
            }
        }
    }

    // Periodically stop+restart discovery so Android NSD doesn't go stale and miss
    // services that come online after we started browsing.
    private fun startPeriodicRefresh() {
        refreshJob?.cancel()
        refreshJob = retryScope.launch {
            while (isActive && isWanted.get()) {
                delay(REFRESH_INTERVAL_MS)
                if (!isWanted.get()) break
                if (isRunning.get()) {
                    SnagInternalLogger.d("Periodic NSD discovery refresh")
                    try {
                        nsdManager?.stopServiceDiscovery(nsdDiscoveryListener)
                        // onDiscoveryStopped will trigger a fresh discoverServices.
                    } catch (e: Exception) {
                        SnagInternalLogger.w("Refresh stopServiceDiscovery failed: $e")
                    }
                } else {
                    // Not running for some reason — just kick off a start.
                    invokeDiscoverServices()
                }
            }
        }
    }

    companion object {
        private const val REFRESH_INTERVAL_MS = 30_000L
        private const val MAX_RETRY_BACKOFF_STEPS = 4 // 1s, 2s, 4s, 8s, 16s
        private const val MAX_RETRY_BACKOFF_MS = 16_000L
    }
}

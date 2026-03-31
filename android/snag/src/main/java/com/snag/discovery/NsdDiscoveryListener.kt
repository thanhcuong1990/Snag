package com.snag.discovery

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import com.snag.core.log.SnagInternalLogger

internal interface NsdDiscoveryListener : NsdManager.DiscoveryListener {
    override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
        SnagInternalLogger.d("onStartDiscoveryFailed for $serviceType with errorCode $errorCode")
    }

    override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {
        SnagInternalLogger.d("onStopDiscoveryFailed for $serviceType with errorCode $errorCode")
    }

    override fun onDiscoveryStarted(serviceType: String?) {
        SnagInternalLogger.d("onDiscoveryStarted for $serviceType")
    }

    override fun onDiscoveryStopped(serviceType: String?) {
        SnagInternalLogger.d("onDiscoveryStopped for $serviceType")
    }

    override fun onServiceFound(serviceInfo: NsdServiceInfo?) {
        SnagInternalLogger.d("onServiceFound for $serviceInfo")
    }

    override fun onServiceLost(serviceInfo: NsdServiceInfo?) {
        SnagInternalLogger.d("onServiceLost for $serviceInfo")
    }
}

package com.snag.discovery

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import timber.log.Timber

internal interface NsdDiscoveryListener : NsdManager.DiscoveryListener {
    override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
        Timber.d("onStartDiscoveryFailed for $serviceType with errorCode $errorCode")
    }

    override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {
        Timber.d("onStopDiscoveryFailed for $serviceType with errorCode $errorCode")
    }

    override fun onDiscoveryStarted(serviceType: String?) {
        Timber.d("onDiscoveryStarted for $serviceType")
    }

    override fun onDiscoveryStopped(serviceType: String?) {
        Timber.d("onDiscoveryStopped for $serviceType")
    }

    override fun onServiceFound(serviceInfo: NsdServiceInfo?) {
        Timber.d("onServiceFound for $serviceInfo")
    }

    override fun onServiceLost(serviceInfo: NsdServiceInfo?) {
        Timber.d("onServiceLost for $serviceInfo")
    }
}

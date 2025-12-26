package com.snag.core.discovery

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import timber.log.Timber

internal interface NsdResolveListener : NsdManager.ResolveListener {
    override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {
        Timber.d("onResolveFailed for $serviceInfo with errorCode $errorCode")
    }

    override fun onServiceResolved(serviceInfo: NsdServiceInfo?) {
        Timber.d("onServiceResolved for $serviceInfo")
    }
}

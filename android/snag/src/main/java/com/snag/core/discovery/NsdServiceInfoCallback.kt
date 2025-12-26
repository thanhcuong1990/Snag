package com.snag.core.discovery

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import androidx.annotation.RequiresApi
import timber.log.Timber

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
internal interface NsdServiceInfoCallback : NsdManager.ServiceInfoCallback {
    override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
        Timber.d("onServiceInfoCallbackRegistrationFailed with errorCode $errorCode")
    }

    override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
        Timber.d("onServiceUpdated for $serviceInfo")
    }

    override fun onServiceLost() {
        Timber.d("onServiceLost")
    }

    override fun onServiceInfoCallbackUnregistered() {
        Timber.d("onServiceInfoCallbackUnregistered")
    }
}

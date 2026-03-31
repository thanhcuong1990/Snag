package com.snag.discovery

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import androidx.annotation.RequiresApi
import com.snag.core.log.SnagInternalLogger

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
internal interface NsdServiceInfoCallback : NsdManager.ServiceInfoCallback {
    override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
        SnagInternalLogger.d("onServiceInfoCallbackRegistrationFailed with errorCode $errorCode")
    }

    override fun onServiceUpdated(serviceInfo: NsdServiceInfo) {
        SnagInternalLogger.d("onServiceUpdated for $serviceInfo")
    }

    override fun onServiceLost() {
        SnagInternalLogger.d("onServiceLost")
    }

    override fun onServiceInfoCallbackUnregistered() {
        SnagInternalLogger.d("onServiceInfoCallbackUnregistered")
    }
}

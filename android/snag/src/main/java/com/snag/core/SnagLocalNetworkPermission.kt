package com.snag.core

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Asks for local network access once per process, from the first activity that resumes.
 *
 * Android 17 blocks connections to private addresses (the emulator's host alias, a Mac on the same
 * Wi-Fi) for apps targeting API 37 unless ACCESS_LOCAL_NETWORK is granted, and it is a runtime
 * permission. Without it every connection attempt times out silently. The debug-host retry loop
 * picks the connection up as soon as the user grants it, so no relaunch is needed.
 */
internal object SnagLocalNetworkPermission {
    private const val PERMISSION = "android.permission.ACCESS_LOCAL_NETWORK"
    private const val FIRST_ENFORCING_SDK = 37
    private const val REQUEST_CODE = 0x534E
    private val registered = AtomicBoolean(false)

    fun requestWhenNeeded(context: Context) {
        val application = context.applicationContext as? Application ?: return
        if (!isRequired(application) || !registered.compareAndSet(false, true)) return
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                application.unregisterActivityLifecycleCallbacks(this)
                if (isRequired(activity)) activity.requestPermissions(arrayOf(PERMISSION), REQUEST_CODE)
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }

    private fun isRequired(context: Context): Boolean =
        Build.VERSION.SDK_INT >= FIRST_ENFORCING_SDK &&
            context.applicationInfo.targetSdkVersion >= FIRST_ENFORCING_SDK &&
            context.checkSelfPermission(PERMISSION) != PackageManager.PERMISSION_GRANTED
}

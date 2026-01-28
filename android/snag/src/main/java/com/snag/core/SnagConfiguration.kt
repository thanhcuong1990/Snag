package com.snag.core

import android.content.Context
import android.os.Build

data class SnagConfiguration(
    val projectName: String,
    val netServiceType: String = "_Snag._tcp",
    val debugHost: String? = null,
    val debugPort: Int = 43435,
    val enableLogs: Boolean = true,
    val isSecurityEnabled: Boolean = true,
    val securityPIN: String? = null
) {
    companion object {
        fun getDefault(context: Context): SnagConfiguration {
            val isEmulator = Build.PRODUCT.contains("sdk") ||
                    Build.PRODUCT.contains("emulator") ||
                    Build.DEVICE.contains("generic") ||
                    Build.FINGERPRINT.contains("generic") ||
                    Build.FINGERPRINT.contains("unknown") ||
                    Build.HARDWARE.contains("goldfish") ||
                    Build.HARDWARE.contains("ranchu") ||
                    Build.MODEL.contains("google_sdk") ||
                    Build.MODEL.contains("Emulator") ||
                    Build.MODEL.contains("Android SDK built for x86") ||
                    Build.MANUFACTURER.contains("Genymotion")

            val metaData = try {
                context.packageManager.getApplicationInfo(
                    context.packageName,
                    android.content.pm.PackageManager.GET_META_DATA
                ).metaData
            } catch (e: Exception) {
                null
            }

            val manifestPin = metaData?.get("com.snag.SECURITY_PIN")?.toString()
            val securityEnabled = metaData?.getBoolean("com.snag.SECURITY_ENABLED", true) ?: true
            
            // Check System Property as a fallback (similar to iOS environment/launch args)
            val systemPin = System.getProperty("SnagSecurityPIN")

            return SnagConfiguration(
                projectName = context.applicationInfo.loadLabel(context.packageManager).toString(),
                debugHost = if (isEmulator) "10.0.2.2" else null,
                isSecurityEnabled = securityEnabled,
                securityPIN = systemPin ?: manifestPin
            )
        }
    }
}

package com.snag.core

import android.content.Context
import android.os.Build

data class SnagConfiguration(
    val projectName: String,
    val netServiceType: String = "_Snag._tcp",
    val debugHost: String? = null,
    val debugPort: Int = 43435,
    val enableLogs: Boolean = true
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

            return SnagConfiguration(
                projectName = context.applicationInfo.loadLabel(context.packageManager).toString(),
                debugHost = if (isEmulator) "10.0.2.2" else null
            )
        }
    }
}

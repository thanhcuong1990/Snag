package com.snag.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.util.Base64
import androidx.core.graphics.createBitmap
import com.snag.models.SnagDevice
import com.snag.models.SnagProject
import java.io.ByteArrayOutputStream

object SnagAppMetadataProvider {

    fun getDevice(context: Context): SnagDevice {
        val deviceName = getDeviceName(context)
        val model = Build.MODEL
        
        // Use model as hostName for Android to avoid build hash, 
        // but only if it's different from the device name to avoid redundancy.
        val hostName = if (deviceName.caseInsensitiveCompare(model) != 0) {
            model
        } else {
            // If they are the same, try to use the product or brand for some distinction
            "${Build.MANUFACTURER} ${Build.PRODUCT}"
        }
        
        val ip = getIpAddress() ?: "unknown"
        val deviceDescription = "Android ${Build.VERSION.RELEASE}"
        
        return SnagDevice(
            deviceName = deviceName,
            deviceDescription = deviceDescription,
            deviceId = "$hostName-$deviceName-$deviceDescription-$ip",
            hostName = hostName,
            ip = ip
        )
    }

    private fun getHostName(): String {
        // Build.HOST usually returns the build machine name or a hash.
        // On Android, we don't have a reliable user-facing "hostname" like iOS,
        // so we use Build properties that are more readable.
        return Build.MODEL
    }

    private fun getIpAddress(): String? {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
            val interfaceList = interfaces.toList()
            
            // First pass: look for IPv4 on wifi or ethernet
            for (networkInterface in interfaceList) {
                val name = networkInterface.name.lowercase()
                if (name.contains("wlan") || name.contains("eth") || name.contains("en0") || name.contains("en1")) {
                    val addresses = networkInterface.inetAddresses
                    while (addresses.hasMoreElements()) {
                        val address = addresses.nextElement()
                        if (!address.isLoopbackAddress && address is java.net.Inet4Address) {
                            return address.hostAddress
                        }
                    }
                }
            }
            
            // Second pass: any IPv4
            for (networkInterface in interfaceList) {
                val addresses = networkInterface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()
                    if (!address.isLoopbackAddress && address is java.net.Inet4Address) {
                        return address.hostAddress
                    }
                }
            }
            
            // Third pass: any IPv6 as last resort
            for (networkInterface in interfaceList) {
                val addresses = networkInterface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()
                    if (!address.isLoopbackAddress) {
                        return address.hostAddress
                    }
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
        return null
    }

    private fun getDeviceName(context: Context): String {
        val model = Build.MODEL
        val isEmulator = isEmulator()
        
        // Try to get user-assigned name first
        val deviceName = android.provider.Settings.Global.getString(context.contentResolver, "device_name")
        
        // On real devices, if the user assigned a name (different from the model name), use it.
        if (!isEmulator && !deviceName.isNullOrBlank() && deviceName.caseInsensitiveCompare(model) != 0) {
            return deviceName
        }
        
        // For emulators or if custom name is same as model/missing
        if (isEmulator) {
            // If the model is a generic "sdk_gphone...", provide a friendlier name
            if (model.startsWith("sdk_gphone") || model.contains("Emulator") || model.contains("Android SDK")) {
                return "Android Emulator"
            }
        }
        
        return model
    }

    private fun String.caseInsensitiveCompare(other: String): Int {
        return this.lowercase().compareTo(other.lowercase())
    }

    private fun isEmulator(): Boolean {
        return (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"))
                || Build.FINGERPRINT.startsWith("generic")
                || Build.FINGERPRINT.startsWith("unknown")
                || Build.HARDWARE.contains("goldfish")
                || Build.HARDWARE.contains("ranchu")
                || Build.MODEL.contains("google_sdk")
                || Build.MODEL.contains("Emulator")
                || Build.MODEL.contains("Android SDK built for x86")
                || Build.MANUFACTURER.contains("Genymotion")
                || Build.PRODUCT.contains("sdk_google")
                || Build.PRODUCT.contains("google_sdk")
                || Build.PRODUCT.contains("sdk")
                || Build.PRODUCT.contains("sdk_x86")
                || Build.PRODUCT.contains("vbox86p")
                || Build.PRODUCT.contains("emulator")
                || Build.PRODUCT.contains("simulator")
    }

    fun getProject(context: Context, projectName: String): SnagProject {
        return SnagProject(
            projectName = projectName,
            appIcon = getAppIconBase64(context),
            bundleId = context.packageName
        )
    }

    fun isReactNative(): Boolean {
        return try {
            Class.forName("com.facebook.react.bridge.ReactContext")
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun getAppIconBase64(context: Context): String? {
        return try {
            val packageManager = context.packageManager
            val applicationInfo = context.applicationInfo
            val icon = packageManager.getApplicationIcon(applicationInfo)
            
            val bitmap = if (icon is BitmapDrawable) {
                icon.bitmap
            } else {
                val width = icon.intrinsicWidth.takeIf { it > 0 } ?: 100
                val height = icon.intrinsicHeight.takeIf { it > 0 } ?: 100
                val bitmap = createBitmap(width, height)
                val canvas = Canvas(bitmap)
                icon.setBounds(0, 0, canvas.width, canvas.height)
                icon.draw(canvas)
                bitmap
            }
            
            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            val byteArray = outputStream.toByteArray()
            Base64.encodeToString(byteArray, Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }
}

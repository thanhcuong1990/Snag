package com.snag.reactnative

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import com.facebook.react.modules.network.OkHttpClientProvider
import com.snag.Snag

/**
 * Automatically initializes Snag and registers the OkHttp client factory.
 * Includes security guards to ensure it only runs in debuggable builds or on emulators.
 */
class SnagInitializer : ContentProvider() {
    override fun onCreate(): Boolean {
        android.util.Log.d("Snag", "SnagInitializer onCreate called")
        val context = context ?: return false
        
        // Only initialize if debuggable or running on emulator
        val isDebuggable = (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val isEmulator = isEmulator()
        
        if (!isDebuggable && !isEmulator) {
            return true
        }

        // Initialize native Snag
        Snag.start(context)
        
        // Register the OkHttp factory for React Native
        OkHttpClientProvider.setOkHttpClientFactory(SnagOkHttpClientFactory())
        
        return true
    }

    private fun isEmulator(): Boolean {
        val buildProduct = android.os.Build.PRODUCT
        val buildModel = android.os.Build.MODEL
        val buildHardware = android.os.Build.HARDWARE
        val buildFingerprint = android.os.Build.FINGERPRINT
        val buildManufacturer = android.os.Build.MANUFACTURER
        val buildDevice = android.os.Build.DEVICE
        
        return buildProduct.contains("sdk") ||
                buildProduct.contains("emulator") ||
                buildDevice.contains("generic") ||
                buildFingerprint.contains("generic") ||
                buildFingerprint.contains("unknown") ||
                buildHardware.contains("goldfish") ||
                buildHardware.contains("ranchu") ||
                buildModel.contains("google_sdk") ||
                buildModel.contains("Emulator") ||
                buildModel.contains("Android SDK built for x86") ||
                buildManufacturer.contains("Genymotion")
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}

package com.snag

import android.content.Context
import androidx.startup.Initializer

/**
 * Automatically initializes Snag and registers the OkHttp client factory for React Native if present.
 */
class SnagInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        // Only initialize if debuggable or running on emulator
        val isDebuggable = (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val isEmulator = isEmulator()
        val isEnabledInManifest = try {
            val appInfo = context.packageManager.getApplicationInfo(context.packageName, android.content.pm.PackageManager.GET_META_DATA)
            appInfo.metaData?.getBoolean("com.snag.ENABLED", false) ?: false
        } catch (e: Exception) {
            false
        }
        
        if (!isDebuggable && !isEmulator && !isEnabledInManifest) {
            return
        }

        // Initialize native Snag
        Snag.start(context)

        // Try to hook React Native logs if present
        try {
            hookReactNativeLogs()
        } catch (_: Exception) {}

        // Try to register React Native OkHttp factory if React Native is on the classpath
        try {
            Class.forName("com.facebook.react.modules.network.OkHttpClientProvider")
            registerReactNativeFactory()
        } catch (_: ClassNotFoundException) {
            // React Native not present, skipping
        }
    }

    private fun hookReactNativeLogs() {
        try {
            val fLogClass = Class.forName("com.facebook.common.logging.FLog")
            val loggingDelegateInterface = Class.forName("com.facebook.common.logging.LoggingDelegate")
            
            val proxy = java.lang.reflect.Proxy.newProxyInstance(
                loggingDelegateInterface.classLoader,
                arrayOf(loggingDelegateInterface)
            ) { _, method, args ->
                if (args != null && args.size >= 2 && args[0] is String && args[1] is String) {
                    val tag = args[0] as String
                    val msg = args[1] as String
                    
                    val level = when (method.name) {
                        "v", "verbose" -> "verbose"
                        "d", "debug" -> "debug"
                        "i", "info" -> "info"
                        "w", "warn" -> "warn"
                        "e", "error", "wtf" -> "error"
                        else -> "info"
                    }
                    
                    if (!msg.contains("Snag:") && !tag.contains("Snag")) {
                        Snag.log(msg, level, tag)
                    }
                }
                
                // Return default values for primitive return types to avoid NPE on unboxing
                when (method.returnType) {
                    Boolean::class.javaPrimitiveType -> true
                    Int::class.javaPrimitiveType -> 2 // VERBOSE
                    else -> null
                }
            }
            
            val setDelegateMethod = fLogClass.getDeclaredMethod("setLoggingDelegate", loggingDelegateInterface)
            setDelegateMethod.invoke(null, proxy)
        } catch (_: Exception) {
            // FLog not on classpath
        }
    }

    private fun registerReactNativeFactory() {
        try {
            com.facebook.react.modules.network.OkHttpClientProvider.setOkHttpClientFactory(SnagOkHttpClientFactory())
        } catch (e: Throwable) {
            android.util.Log.e("Snag", "Failed to register SnagOkHttpClientFactory", e)
        }
    }

    private fun isEmulator(): Boolean {
        return (android.os.Build.BRAND.startsWith("generic") && android.os.Build.DEVICE.startsWith("generic")) ||
                android.os.Build.FINGERPRINT.startsWith("generic") ||
                android.os.Build.FINGERPRINT.startsWith("unknown") ||
                android.os.Build.HARDWARE.contains("goldfish") ||
                android.os.Build.HARDWARE.contains("ranchu") ||
                android.os.Build.MODEL.contains("google_sdk") ||
                android.os.Build.MODEL.contains("Emulator") ||
                android.os.Build.MODEL.contains("Android SDK built for x86") ||
                android.os.Build.MANUFACTURER.contains("Genymotion") ||
                android.os.Build.PRODUCT.contains("sdk_google") ||
                android.os.Build.PRODUCT.contains("google_sdk") ||
                android.os.Build.PRODUCT.contains("sdk") ||
                android.os.Build.PRODUCT.contains("sdk_x86") ||
                android.os.Build.PRODUCT.contains("vbox86p") ||
                android.os.Build.PRODUCT.contains("emulator") ||
                android.os.Build.PRODUCT.contains("simulator")
    }

    override fun dependencies(): List<Class<out Initializer<*>>> = emptyList()
}

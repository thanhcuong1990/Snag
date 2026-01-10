package com.snag

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.util.Base64
import com.snag.core.browser.Browser
import com.snag.core.browser.BrowserImpl
import com.snag.core.config.Config
import com.snag.models.Device
import com.snag.models.Project
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

object Snag {
    @JvmStatic
    @JvmOverloads
    fun start(
        context: Context,
        config: Config = Config.getDefault(context)
    ) {
        if (Browser.isInitialized()) return
        val device = Device(
            deviceName = Build.MODEL,
            deviceDescription = "Android ${Build.VERSION.RELEASE}",
            deviceId = "${Build.MANUFACTURER}-${Build.MODEL}-android-${Build.VERSION.RELEASE}"
        )
        val project = Project(
            projectName = config.projectName,
            appIcon = getAppIconBase64(context)
        )

        val browser = BrowserImpl(
            context = context.applicationContext,
            config = config,
            project = project,
            device = device
        )
        Browser.initialize(browser)
        
        if (config.enableLogs) {
            enableAutoLogCapture()
        }
    }

    @JvmStatic
    fun isEnabled(): Boolean {
        return try {
            Browser.getInstance()
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Helper to manually add Snag interceptor to your OkHttpClient.Builder.
     * Use this if you are not using React Native's default OkHttpClient or want to add it to a specific client.
     */
    @JvmStatic
    fun addInterceptor(builder: okhttp3.OkHttpClient.Builder) {
        // Prevent duplicate interceptors
        if (builder.interceptors().none { it is SnagInterceptor }) {
            builder.addInterceptor(SnagInterceptor.getInstance())
        }
    }

    @JvmStatic
    @JvmOverloads
    fun log(
        message: String,
        level: String = "info",
        tag: String? = null,
        details: Map<String, String>? = null
    ) {
        try {
            Browser.getInstance().sendLog(
                com.snag.models.SnagLog(
                    level = level,
                    message = message,
                    tag = tag,
                    details = details
                )
            )
        } catch (_: Exception) {
            // Snag not initialized or failed
        }
    }

    @JvmStatic
    fun enableAutoLogCapture() {
        MainScope().launch(Dispatchers.IO) {
            var process: Process? = null
            try {
                process = Runtime.getRuntime().exec("logcat -v threadtime -v year -v zone")
                val reader = java.io.BufferedReader(java.io.InputStreamReader(process.inputStream))
                
                val pid = android.os.Process.myPid().toString()
                
                reader.use { bufferedReader ->
                    var line: String?
                    while (bufferedReader.readLine().also { line = it } != null) {
                        val currentLine = line ?: continue
                        if (currentLine.contains(pid)) {
                            // Prevent infinite loop by filtering out Snag's own network/log activity
                            // and OkHttp's logging which can cause feedback loops
                            if (currentLine.contains("BrowserImpl") || 
                                currentLine.contains("SnagLog") ||
                                currentLine.contains("Snag: Connecting") || 
                                currentLine.contains("Snag: Connected") ||
                                currentLine.contains("Redefining intrinsic method") ||
                                currentLine.contains("OkHttpClient") ||
                                currentLine.contains("okhttp3") ||
                                currentLine.contains("ReactNativeJS") ||
                                currentLine.contains("React Native") ||
                                currentLine.contains("resource failed to call close") ||
                                currentLine.contains("Choreographer") ||
                                currentLine.contains("Skipped") && currentLine.contains("frames")) {
                                continue
                            }

                            // Logcat format with -v threadtime -v year -v zone:
                            // 2026-01-10 16:03:42.246 +0700  4758  4879 W ReactNativeJS: message
                            val logcatRegex = Regex("""^.*?\s+\d+\s+\d+\s+([VDIWEF])\s+(.*?):\s?(.*)$""")
                            val match = logcatRegex.find(currentLine)
                            
                            if (match != null) {
                                val levelChar = match.groupValues[1]
                                var tag = match.groupValues[2].trim()
                                val message = match.groupValues[3]
                                
                                val logLevel = when (levelChar) {
                                    "V" -> "verbose"
                                    "D" -> "debug"
                                    "I" -> "info"
                                    "W" -> "warn"
                                    "E" -> "error"
                                    "F" -> "fatal"
                                    else -> "info"
                                }
                                
                                // Map React Native native tag to our friendly name
                                if (tag == "ReactNativeJS") {
                                    tag = "React Native"
                                }
                                
                                log(message, level = logLevel, tag = tag)
                            } else {
                                // Fallback for unexpected formats
                                log(currentLine, level = "verbose", tag = "logcat")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore
            } finally {
                process?.destroy()
            }
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
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
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
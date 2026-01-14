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
import androidx.core.graphics.createBitmap

object Snag {
    private lateinit var appContext: Context
    private lateinit var device: Device
    private lateinit var project: Project
    private var isStreamingLogs = false

    @JvmStatic
    @JvmOverloads
    fun start(
        context: Context,
        config: Config = Config.getDefault(context)
    ) {
        this.appContext = context.applicationContext
        this.device = Device(
            deviceName = Build.MODEL,
            deviceDescription = "Android ${Build.VERSION.RELEASE}",
            deviceId = "${Build.MANUFACTURER}-${Build.MODEL}-android-${Build.VERSION.RELEASE}"
        )
        this.project = Project(
            projectName = config.projectName,
            appIcon = getAppIconBase64(context)
        )

        val browser = BrowserImpl(
            context = appContext,
            config = config,
            project = project,
            device = device
        )
        Browser.initialize(browser)

        browser.addPacketListener { packet ->
            packet.control?.let { handleControl(it) }
        }

        // Request initial log streaming status
        browser.sendPacket(com.snag.models.Packet(
            control = com.snag.models.Control(type = "logStreamingStatusRequest"),
            device = device,
            project = project
        ))
        
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
            val pid = android.os.Process.myPid().toString()
            val pidPattern = Regex("""\b$pid\b""") // Match PID as a whole word

            while (true) {
                var process: Process? = null
                try {
                    // Try with year/zone first, if fails, fallback to simpler threadtime
                    val formats = listOf("-v threadtime -v year -v zone", "-v threadtime", "-v time")
                    var success = false
                    
                    // Accumulator for multi-line logs (e.g., pretty-printed JSON)
                    var pendingLog: StringBuilder? = null
                    var pendingLevel: String? = null
                    var pendingTag: String? = null
                    
                    fun flushPendingLog() {
                        pendingLog?.let { buffer ->
                            if (buffer.isNotEmpty()) {
                                log(buffer.toString(), level = pendingLevel ?: "info", tag = pendingTag)
                            }
                        }
                        pendingLog = null
                        pendingLevel = null
                        pendingTag = null
                    }
                    
                    for (format in formats) {
                        try {
                            process = Runtime.getRuntime().exec("logcat $format")
                            val reader = java.io.BufferedReader(java.io.InputStreamReader(process.inputStream))
                            
                            reader.use { bufferedReader ->
                                var line: String?
                                while (bufferedReader.readLine().also { line = it } != null) {
                                    val currentLine = line ?: continue
                                    
                                    // More resilient PID check
                                    if (pidPattern.containsMatchIn(currentLine)) {
                                        // React Native JS logs (console.log from JS) should always be sent
                                        val isReactNativeJSLog = currentLine.contains("ReactNativeJS")
                                        
                                        // Skip non-RN logs if streaming is paused
                                        if (!isStreamingLogs && !isReactNativeJSLog) continue
                                        if (currentLine.contains("BrowserImpl") || 
                                            currentLine.contains("SnagLog") ||
                                            currentLine.contains("Snag: Connecting") || 
                                            currentLine.contains("Snag: Connected") ||
                                            currentLine.contains("Redefining intrinsic method") ||
                                            currentLine.contains("OkHttpClient") ||
                                            currentLine.contains("okhttp3") ||
                                            currentLine.contains("resource failed to call close") ||
                                            currentLine.contains("Choreographer") ||
                                            currentLine.contains("Skipped") && currentLine.contains("frames")) {
                                            continue
                                        }

                                        // Flexible regex for various logcat formats: ([VDIWEF]) (Tag): (Message)
                                        // Some formats include PID/TID/Date/Time before the level
                                        val logcatRegex = Regex("""([VDIWEF])\s+(.*?):\s?(.*)$""")
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
                                            
                                            // Handle both native tags and consolidated JS logs
                                            val isRNLog = tag.contains("ReactNative") || tag.contains("ReactNativeJS")
                                            if (isRNLog) {
                                                tag = "React Native"
                                            }
                                            
                                            val trimmedMessage = message.trim()
                                            
                                            // Check if this is a JSON continuation line for RN logs
                                            // JSON continuations: lines that are just braces, brackets, or "key": value patterns
                                            val isJsonContinuation = pendingLog != null && isRNLog && (
                                                trimmedMessage == "{" || trimmedMessage == "}" ||
                                                trimmedMessage == "[" || trimmedMessage == "]" ||
                                                trimmedMessage == "}," || trimmedMessage == "]," ||
                                                trimmedMessage.matches(Regex("""^\s*"[^"]+"\s*:.*""")) || // "key": value
                                                trimmedMessage.matches(Regex("""^\s*[\[\{}\],].*""")) || // starts with JSON punctuation
                                                trimmedMessage.matches(Regex("""^\s*\d+.*""")) || // array item (number)
                                                trimmedMessage.matches(Regex("""^\s*"[^"]*"[,\s]*$""")) || // string array item
                                                trimmedMessage.matches(Regex("""^\s*null[,\s]*$""")) ||
                                                trimmedMessage.matches(Regex("""^\s*(true|false)[,\s]*$"""))
                                            )
                                            
                                            if (isJsonContinuation) {
                                                // Append to pending log
                                                pendingLog?.append("\n")?.append(message)
                                            } else {
                                                // This is a new log line - flush any pending multi-line log first
                                                flushPendingLog()
                                                
                                                // Check if this starts a new multi-line JSON (for RN logs)
                                                val containsJsonStart = trimmedMessage.contains("{") || trimmedMessage.contains("[")
                                                val endsWithJsonEnd = trimmedMessage.endsWith("}") || trimmedMessage.endsWith("]")
                                                val startsMultiLineJson = isRNLog && containsJsonStart && !endsWithJsonEnd
                                                
                                                if (startsMultiLineJson) {
                                                    // Start accumulating multi-line log
                                                    pendingLog = StringBuilder(message)
                                                    pendingLevel = logLevel
                                                    pendingTag = tag
                                                } else {
                                                    log(message, level = logLevel, tag = tag)
                                                }
                                            }
                                            success = true
                                        } else if (pendingLog != null) {
                                            // This line doesn't match logcat format - likely continuation of multi-line
                                            pendingLog?.append("\n")?.append(currentLine.trim())
                                        } else if (!currentLine.contains("Beginning of main")) {
                                            // Optional: log non-matching lines as 'logcat' if they look like logs
                                            log(currentLine, level = "verbose", tag = "logcat")
                                            success = true
                                        }
                                    } else if (pendingLog != null) {
                                        // Line doesn't have our PID but we're accumulating - likely JSON continuation
                                        // Check if it looks like JSON content (not a new logcat line from another process)
                                        val trimmed = currentLine.trim()
                                        if (trimmed.isNotEmpty() && !Regex("""^\d{4}-\d{2}-\d{2}""").containsMatchIn(currentLine)) {
                                            pendingLog?.append("\n")?.append(trimmed)
                                        }
                                    }
                                }
                                // Flush any remaining pending log when reader closes
                                flushPendingLog()
                            }
                        } catch (e: Exception) {
                            continue // Try next format
                        }
                    }
                } catch (e: Exception) {
                    // Ignore and retry after delay
                } finally {
                    process?.destroy()
                }
                
                // If we reach here, logcat process died or we couldn't start it. Retry after delay.
                kotlinx.coroutines.delay(2000)
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

    private fun handleControl(control: com.snag.models.Control) {
        when (control.type) {
            "appInfoRequest" -> sendAppInfo()
            "logStreamingControl" -> {
                isStreamingLogs = control.shouldStreamLogs ?: false
            }
        }
    }

    private fun sendAppInfo() {
        val appInfo = com.snag.models.AppInfo(
            bundleId = appContext.packageName,
            isReactNative = isReactNative()
        )
        try {
            Browser.getInstance().sendPacket(com.snag.models.Packet(
                control = com.snag.models.Control(type = "appInfoResponse", appInfo = appInfo),
                device = device,
                project = project
            ))
        } catch (_: Exception) {}
    }

    private fun isReactNative(): Boolean {
        return try {
            Class.forName("com.facebook.react.bridge.ReactContext")
            true
        } catch (_: Exception) {
            false
        }
    }
}
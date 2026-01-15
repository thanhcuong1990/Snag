package com.snag.core.log

import com.snag.network.SnagBrowser
import com.snag.models.SnagLog
import kotlinx.coroutines.*

object SnagLogcatManager {
    private var isStreamingLogs = false
    private var captureJob: Job? = null
    private val scope = MainScope()

    fun setStreamingEnabled(enabled: Boolean) {
        isStreamingLogs = enabled
    }

    fun isStreamingEnabled(): Boolean = isStreamingLogs

    fun startAutoLogCapture() {
        if (captureJob?.isActive == true) return
        
        captureJob = scope.launch(Dispatchers.IO) {
            val pid = android.os.Process.myPid().toString()
            val pidPattern = Regex("""\b$pid\b""")
            
            val accumulator = LogAccumulator { message, level, tag ->
                sendLog(message, level, tag)
            }
            
            val reader = LogcatReader(coroutineContext)

            while (isActive) {
                try {
                    reader.readStream { line ->
                        accumulator.processLine(line, isStreamingLogs, pidPattern)
                    }
                } catch (e: Exception) {
                    // Log error if needed, and retry
                } finally {
                    accumulator.flush()
                }
                delay(2000)
            }
        }
    }

    private fun sendLog(
        message: String,
        level: String = "info",
        tag: String? = null,
        details: Map<String, String>? = null
    ) {
        try {
            SnagBrowser.getInstance().sendLog(
                SnagLog(
                    level = level,
                    message = message,
                    tag = tag,
                    details = details
                )
            )
        } catch (_: Exception) { }
    }
}

package com.snag.core.log

object LogFilter {
    private val IGNORED_TERMS = setOf(
        "BrowserImpl",
        "SnagLog",
        "Snag: Connecting",
        "Snag: Connected",
        "Redefining intrinsic method",
        "OkHttpClient",
        "okhttp3",
        "resource failed to call close",
        "Choreographer",
    )

    fun shouldIgnore(line: String, isStreamingLogs: Boolean): Boolean {
        // Fast path: if not streaming and not a JS log, ignore immediately
        val isReactNativeJSLog = line.contains("ReactNativeJS")
        if (!isStreamingLogs && !isReactNativeJSLog) return true

        // Filter out Snag's own noise and other system noise
        if (IGNORED_TERMS.any { line.contains(it) }) return true
        
        // specific complex check
        if (line.contains("Skipped") && line.contains("frames")) return true

        return false
    }
}

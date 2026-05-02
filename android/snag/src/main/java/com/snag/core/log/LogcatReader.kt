package com.snag.core.log

import kotlinx.coroutines.isActive
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.coroutines.CoroutineContext

class LogcatReader(
    private val coroutineContext: CoroutineContext
) {
    @Volatile
    private var activeProcess: Process? = null

    fun readStream(onLine: (String) -> Unit) {
        val format = chosenFormat ?: probeFormat() ?: return
        if (!coroutineContext.isActive) return

        var process: Process? = null
        try {
            process = Runtime.getRuntime().exec("logcat $format")
            activeProcess = process
            BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    if (!coroutineContext.isActive) break
                    onLine(line!!)
                }
            }
        } catch (e: Exception) {
            synchronized(this::class.java) { chosenFormat = null }
        } finally {
            activeProcess = null
            process?.destroy()
        }
    }

    /** Tears down the long-running logcat process if active. */
    fun stop() {
        activeProcess?.destroy()
        activeProcess = null
    }

    private fun probeFormat(): String? {
        for (format in CANDIDATE_FORMATS) {
            if (!coroutineContext.isActive) return null

            var process: Process? = null
            try {
                process = Runtime.getRuntime().exec("logcat -d -t 1 $format")
                val exited = process.waitFor()
                if (exited == 0) {
                    synchronized(this::class.java) { chosenFormat = format }
                    return format
                }
            } catch (_: Exception) {
                // try next format
            } finally {
                process?.destroy()
            }
        }
        return null
    }

    companion object {
        private val CANDIDATE_FORMATS = listOf(
            "-v threadtime -v year -v zone",
            "-v threadtime",
            "-v time"
        )

        @Volatile
        private var chosenFormat: String? = null
    }
}

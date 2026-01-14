package com.snag.core.log

import kotlinx.coroutines.isActive
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.coroutines.CoroutineContext

class LogcatReader(
    private val coroutineContext: CoroutineContext
) {
    private val formats = listOf("-v threadtime -v year -v zone", "-v threadtime", "-v time")

    fun readStream(onLine: (String) -> Unit) {
        for (format in formats) {
            if (!coroutineContext.isActive) break
            
            var process: Process? = null
            try {
                process = Runtime.getRuntime().exec("logcat $format")
                val reader = BufferedReader(InputStreamReader(process.inputStream))
                
                reader.use { bufferedReader ->
                    var line: String?
                    while (bufferedReader.readLine().also { line = it } != null) {
                        if (!coroutineContext.isActive) break
                        onLine(line!!)
                    }
                }
            } catch (e: Exception) {
                // Try next format
                continue
            } finally {
                process?.destroy()
            }
        }
    }
}

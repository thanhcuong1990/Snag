package com.snag.core.log

import com.snag.core.browser.Browser
import com.snag.models.SnagLog

class LogAccumulator(
    private val sendLogFn: (String, String, String?) -> Unit
) {
    private var pendingLog: StringBuilder? = null
    private var pendingLevel: String? = null
    private var pendingTag: String? = null
    private var currentBalance = 0
    private var bufferedLineCount = 0

    companion object {
        private const val MAX_BUFFER_LINES = 1000
    }

    fun processLine(currentLine: String, isStreamingLogs: Boolean, pidPattern: Regex) {
        if (pidPattern.containsMatchIn(currentLine)) {
            if (LogFilter.shouldIgnore(currentLine, isStreamingLogs)) return

            val parsed = LogParser.parse(currentLine)
            
            if (parsed != null) {
                val isRNLog = parsed.tag == "React Native"
                
                if (pendingLog != null && isRNLog) {
                    accumulate(parsed.message)
                    currentBalance += LogParser.calculateBalanceChange(parsed.message)
                    checkFlush()
                } else {
                    if (pendingLog != null) flush()
                    
                    val balanceChange = if (isRNLog) LogParser.calculateBalanceChange(parsed.message) else 0
                    if (balanceChange > 0) {
                        startNew(parsed.message, parsed.level, parsed.tag, balanceChange)
                    } else {
                        sendLogFn(parsed.message, parsed.level, parsed.tag)
                    }
                }
            } else if (pendingLog != null) {
                if (LogParser.isLikelyContentLine(currentLine)) {
                    accumulate(currentLine.trim())
                    currentBalance += LogParser.calculateBalanceChange(currentLine)
                    checkFlush()
                }
            } else if (!currentLine.contains("Beginning of main")) {
                sendLogFn(currentLine, "verbose", "logcat")
            }
        } else if (pendingLog != null) {
            if (LogParser.isLikelyContentLine(currentLine)) {
                accumulate(currentLine.trim())
                currentBalance += LogParser.calculateBalanceChange(currentLine)
                checkFlush()
            }
        }
    }

    fun flush() {
        pendingLog?.let { buffer ->
            if (buffer.isNotEmpty()) {
                sendLogFn(buffer.toString(), pendingLevel ?: "info", pendingTag)
            }
        }
        reset()
    }

    private fun accumulate(message: String) {
        pendingLog?.append("\n")?.append(message)
        bufferedLineCount++
    }

    private fun startNew(message: String, level: String, tag: String, balance: Int) {
        pendingLog = StringBuilder(message)
        pendingLevel = level
        pendingTag = tag
        currentBalance = balance
        bufferedLineCount = 1
    }

    private fun checkFlush() {
        if (currentBalance <= 0 || bufferedLineCount > MAX_BUFFER_LINES) {
            flush()
        }
    }

    private fun reset() {
        pendingLog = null
        pendingLevel = null
        pendingTag = null
        currentBalance = 0
        bufferedLineCount = 0
    }
}

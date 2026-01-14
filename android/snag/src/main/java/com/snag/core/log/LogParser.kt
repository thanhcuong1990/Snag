package com.snag.core.log

import java.util.regex.Pattern

object LogParser {
    // Compiled patterns for better performance
    private val LOGCAT_PATTERN = Pattern.compile("([VDIWEF])\\s+(.*?):\\s?(.*)$")
    
    // Simple check to avoid counting braces on obvious date lines (unlikely in message but good for safety)
    private val DATE_PREFIX = Pattern.compile("^\\d{4}-\\d{2}-\\d{2}")

    data class ParsedLog(
        val level: String,
        val tag: String,
        val message: String
    )

    fun parse(line: String): ParsedLog? {
        val matcher = LOGCAT_PATTERN.matcher(line)
        if (!matcher.find()) return null

        val levelChar = matcher.group(1) ?: "I"
        var tag = matcher.group(2)?.trim() ?: ""
        val message = matcher.group(3) ?: ""
        
        val logLevel = when (levelChar) {
            "V" -> "verbose"
            "D" -> "debug"
            "I" -> "info"
            "W" -> "warn"
            "E" -> "error"
            "F" -> "fatal"
            else -> "info"
        }

        // Normalize React Native tags
        if (tag.contains("ReactNative") || tag.contains("ReactNativeJS")) {
            tag = "React Native"
        }

        return ParsedLog(logLevel, tag, message)
    }

    /**
     * Calculates the net change in brace/bracket balance for a given line.
     * (+1 for '{' or '[', -1 for '}' or ']')
     * This allows us to track nesting without full JSON parsing.
     */
    fun calculateBalanceChange(message: String): Int {
        var balance = 0
        var insideString = false
        var escaped = false

        for (char in message) {
            if (escaped) {
                escaped = false
                continue
            }

            if (char == '\\') {
                escaped = true
                continue
            }

            if (char == '"') {
                insideString = !insideString
                continue
            }

            if (!insideString) {
                when (char) {
                    '{', '[' -> balance++
                    '}', ']' -> balance--
                }
            }
        }
        return balance
    }

    /**
     * Heuristic to determine if a line (that didn't parse as a standard log) is likely just a content line.
     */
    fun isLikelyContentLine(line: String): Boolean {
        val trimmed = line.trim()
        // If it starts with a date, it's likely a new log line being misparsed (or a system line)
        // If it's empty, ignore.
        return trimmed.isNotEmpty() && !DATE_PREFIX.matcher(line).find()
    }
}

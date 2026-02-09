package com.snag.core

data class SnagIdentityMismatchEvent(
    val serverKey: String,
    val expectedFingerprint: String,
    val actualFingerprint: String,
    val recoveryHint: String = "Call Snag.resetTrustedServers() after confirming trusted server identity."
)

fun interface SnagSecurityListener {
    fun onServerIdentityMismatch(event: SnagIdentityMismatchEvent)
}

package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SnagControl(
    @SerialName("type")
    val type: String, // "appInfoRequest", "appInfoResponse", "logStreamingControl", "logStreamingStatusRequest", "logStreamingStatusResponse"
    @SerialName("appInfo")
    val appInfo: SnagAppInfo? = null,
    @SerialName("shouldStreamLogs")
    val shouldStreamLogs: Boolean? = null,
    
    // Handshake
    @SerialName("deviceId")
    val deviceId: String? = null,
    @SerialName("authMode")
    val authMode: String? = null,
    
    // Encryption (Base64 encoded)
    @SerialName("encryptedPayload")
    val encryptedPayload: String? = null, // Base64
    @SerialName("encryptedNonce")
    val encryptedNonce: String? = null // Base64
)

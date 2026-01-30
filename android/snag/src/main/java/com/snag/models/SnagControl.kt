package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Contextual

@Serializable
data class SnagControl(
    @SerialName("type")
    val type: String, // "appInfoRequest", "appInfoResponse", "logStreamingControl", "logStreamingStatusRequest", "logStreamingStatusResponse"
    @SerialName("appInfo")
    val appInfo: SnagAppInfo? = null,
    @SerialName("shouldStreamLogs")
    val shouldStreamLogs: Boolean? = null,
    @SerialName("authPIN")
    val authPIN: String? = null,
    
    // Handshake
    @SerialName("deviceId")
    val deviceId: String? = null,
    @SerialName("salt")
    val salt: String? = null,
    @SerialName("authHash")
    val authHash: String? = null,
    @SerialName("authMode")
    val authMode: String? = null,
    
    // Encryption (Base64 encoded)
    @SerialName("encryptedPayload")
    val encryptedPayload: String? = null, // Base64
    @SerialName("encryptedNonce")
    val encryptedNonce: String? = null // Base64
)

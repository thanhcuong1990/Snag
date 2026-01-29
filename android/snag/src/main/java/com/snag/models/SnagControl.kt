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
    
    // Encryption (Base64 encoded automatically if ByteString? No, kotlinx ser handles ByteArray as List<Byte>? 
    // Usually Base64 is manual or requires "ByteArray" with custom serializer. 
    // Snag seems to be using standard Json.
    // Let's use Base64 String for simplicity if ByteArray serialization is tricky.
    // Models in iOS used Data, which defaults to Base64 in Swift Codable.
    // In Kotlinx Serialization, ByteArray is not default-base64-friendly in older versions without custom serializer.
    // However, I'll use String vars for payload/nonce assuming I base64 encode/decode manually at boundary.
    // Or I'll allow "encryptedPayload" to be String?
    @SerialName("encryptedPayload")
    val encryptedPayload: String? = null, // Base64
    @SerialName("encryptedNonce")
    val encryptedNonce: String? = null // Base64
)

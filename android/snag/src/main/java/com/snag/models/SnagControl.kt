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
    @SerialName("authPIN")
    val authPIN: String? = null
)

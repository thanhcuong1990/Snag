package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Control(
    @SerialName("type")
    val type: String, // "appInfoRequest", "appInfoResponse", "logStreamingControl", "logStreamingStatusRequest", "logStreamingStatusResponse"
    @SerialName("appInfo")
    val appInfo: AppInfo? = null,
    @SerialName("shouldStreamLogs")
    val shouldStreamLogs: Boolean? = null
)

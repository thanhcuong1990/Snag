package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SnagDevice(
    @SerialName("deviceDescription")
    val deviceDescription: String? = null,
    @SerialName("deviceName")
    val deviceName: String? = null,
    @SerialName("deviceId")
    val deviceId: String? = null
)

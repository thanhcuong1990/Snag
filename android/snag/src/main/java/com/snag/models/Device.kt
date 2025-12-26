package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Device(
    @SerialName("deviceDescription")
    val deviceDescription: String,
    @SerialName("deviceName")
    val deviceName: String,
    @SerialName("deviceId")
    val deviceId: String
)

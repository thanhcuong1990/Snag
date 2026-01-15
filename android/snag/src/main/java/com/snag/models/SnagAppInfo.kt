package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SnagAppInfo(
    @SerialName("bundleId")
    val bundleId: String? = null,
    @SerialName("isReactNative")
    val isReactNative: Boolean = false
)

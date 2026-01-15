package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Date

@Serializable
data class SnagLog(
    @SerialName("timestamp")
    val timestamp: Long = System.currentTimeMillis() / 1000,
    @SerialName("level")
    val level: String,
    @SerialName("message")
    val message: String,
    @SerialName("tag")
    val tag: String? = null,
    @SerialName("details")
    val details: Map<String, String>? = null
)

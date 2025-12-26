package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class RequestInfo(
    @SerialName("url")
    val url: String,
    @SerialName("requestMethod")
    val requestMethod: String,
    @SerialName("requestHeaders")
    val requestHeaders: Map<String, String> = emptyMap(),
    @SerialName("requestBody")
    val requestBody: String? = null,
    @SerialName("responseHeaders")
    val responseHeaders: Map<String, String> = emptyMap(),
    @SerialName("responseData")
    val responseData: String? = null,
    @SerialName("statusCode")
    val statusCode: String? = null,
    @SerialName("startDate")
    val startDate: Double,
    @SerialName("endDate")
    val endDate: Double? = null
)

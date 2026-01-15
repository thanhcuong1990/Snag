package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Project(
    @SerialName("projectName")
    val projectName: String? = null,
    @SerialName("appIcon")
    val appIcon: String? = null,
    @SerialName("bundleId")
    val bundleId: String? = null
)

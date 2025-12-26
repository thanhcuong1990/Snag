package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Project(
    @SerialName("projectName")
    val projectName: String,
    @SerialName("appIcon")
    val appIcon: String? = null
)

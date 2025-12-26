package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class Packet(
    @SerialName("packetId")
    val packetId: String = UUID.randomUUID().toString(),
    @SerialName("requestInfo")
    val requestInfo: RequestInfo? = null,
    @SerialName("device")
    val device: Device,
    @SerialName("project")
    val project: Project
)

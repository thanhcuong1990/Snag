package com.snag.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class SnagPacket(
    @SerialName("packetId")
    val id: String = UUID.randomUUID().toString(),
    @SerialName("requestInfo")
    val requestInfo: SnagRequestInfo? = null,
    @SerialName("device")
    val device: SnagDevice? = null,
    @SerialName("project")
    val project: SnagProject? = null,
    @SerialName("log")
    val log: SnagLog? = null,
    @SerialName("control")
    val control: SnagControl? = null
)

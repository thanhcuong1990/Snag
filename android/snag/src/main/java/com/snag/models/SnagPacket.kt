package com.snag.models

import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class SnagPacket(
    @OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
    @EncodeDefault
    @SerialName("packetId")
    val id: String? = null,
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

/*
 * Inzx stand-in for BitChord's AudioOutputStatus, covering what the ported
 * PrecisionAudioSink publishes: the decoder's output format and whether the
 * output is sample-exact. Kept for the Signal path sheet to read.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 */

package com.music.bitchord.playback

import kotlinx.coroutines.flow.MutableStateFlow

object AudioOutputStatus {
    data class Status(
        val decoderOutputEncoding: String? = null,
        val dspFormat: String = "Float32",
        val dspAvailable: Boolean = true,
        val outputExact: Boolean = false,
        val outputExactDetail: String? = null,
    )

    val current = MutableStateFlow(Status())

    fun publishDsp(
        decoderOutputEncoding: String?,
        dspFormat: String = "Float32",
        dspAvailable: Boolean = true,
    ) {
        current.value = current.value.copy(
            decoderOutputEncoding = decoderOutputEncoding,
            dspFormat = dspFormat,
            dspAvailable = dspAvailable,
        )
    }

    fun publishOutputExactness(exact: Boolean, detail: String?) {
        current.value = current.value.copy(outputExact = exact, outputExactDetail = detail)
    }
}

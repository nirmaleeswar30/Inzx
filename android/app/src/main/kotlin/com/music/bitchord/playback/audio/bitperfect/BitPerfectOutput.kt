/*
 * Inzx stand-in for BitChord's BitPerfectOutput status, as the ported
 * CrossfadeController reads it: Automix never mixes while bit-perfect output
 * is active (a blend changes every sample). Backed by Inzx's own bit-perfect
 * USB mode (com.nirmal.inzx.audio.InzxAudioOutput).
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 */

package com.music.bitchord.playback.audio.bitperfect

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

object BitPerfectOutput {
    data class Status(val active: Boolean = false)

    val status: StateFlow<Status> get() = _status
    private val _status = MutableStateFlow(Status())

    fun setActive(active: Boolean) {
        if (_status.value.active != active) _status.value = Status(active)
    }
}

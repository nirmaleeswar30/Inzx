/*
 * Inzx stand-in for BitChord's ListenTogether, exposing only the "in a
 * party" state Automix reads. In Inzx that's a Jam session, which the Dart
 * side reports through the Automix bridge: like BitChord's party, a Jam never
 * mixes (each member would start the next track at a different moment), so
 * analysis stops while one runs.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 */

package com.music.bitchord.data.listentogether

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object ListenTogether {
    data class State(val inParty: Boolean = false)

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    fun setInJam(inJam: Boolean) {
        _state.value = State(inParty = inJam)
    }
}

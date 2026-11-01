/*
 * Inzx stand-ins for the few BitChord playback pieces the ported
 * CrossfadeController reads that Inzx has no equivalent of (or has under
 * another name). Same names and shapes as BitChord's.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 */

package com.music.bitchord.playback

import androidx.media3.common.MediaItem
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * BitChord's sleep timer can stop "after this track", which the controller
 * honours by fading out instead of mixing. Inzx's sleep timer is time-based
 * only (and lives in Dart), so that mode is never on.
 */
object SleepTimer {
    val afterTrack = MutableStateFlow(false)
    fun cancel() {
        afterTrack.value = false
    }
}

/**
 * Music videos aren't mixed (BitChord's rule). Inzx marks them on the queued
 * item's URI (see InzxQueue).
 */
val MediaItem.isVideoOrigin: Boolean
    get() = localConfiguration?.uri?.getQueryParameter("video") == "1"

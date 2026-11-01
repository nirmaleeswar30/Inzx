/*
 * Inzx stand-in for LastWave's ParametricEqNative, with the API the ported
 * AutoEqController calls. LastWave runs the parametric EQ in its C++ engine;
 * Inzx runs it in ParametricEqProcessor, an ExoPlayer audio processor on
 * every player, which reads what is published here.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 */

package com.lastwave.app.playback.eq

object ParametricEqNative {
    data class NativeFilter(
        val type: Int,
        val frequencyHz: Float,
        val gainDb: Float,
        val q: Float,
        val enabled: Boolean,
    )

    /** The correction that should be running now; read by the processors. */
    data class Published(
        val enabled: Boolean = false,
        val preampDb: Float = 0f,
        val filters: List<NativeFilter> = emptyList(),
    )

    @Volatile var published = Published()
        private set

    /** Bumped on every publish so processors know to rebuild coefficients. */
    @Volatile var version = 0
        private set

    val isAvailable: Boolean get() = true

    fun publish(enabled: Boolean, preampDb: Float, filters: List<NativeFilter>) {
        published = Published(enabled, preampDb, filters)
        version++
    }

    fun isEngaged(): Boolean = published.enabled
}

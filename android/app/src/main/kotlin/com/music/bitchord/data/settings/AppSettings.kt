/*
 * Inzx stand-in for BitChord's AppSettings: only the Automix settings its
 * ported analysis and transition code read, under the same names. Values
 * come from Flutter's shared preferences (written by Inzx's Automix settings
 * page) and follow changes live.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 */

package com.music.bitchord.data.settings

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow

object AppSettings {
    // Keys as the Dart side writes them (shared_preferences adds "flutter.").
    const val KEY_AUTOMIX_ENABLED = "flutter.automix_enabled"
    const val KEY_AUTOMIX_PERFORMANCE_MODE = "flutter.automix_performance_mode"

    /** Automix on/off (BitChord: "smart fade"). */
    val smartFadeEnabled = MutableStateFlow(false)

    /** The CPU budget used by Beat This! and vocal analysis for Automix. */
    val automixPerformanceMode = MutableStateFlow(AutomixPerformanceMode.BALANCED)

    // ---- Read by the transition engine (set from Dart) -------------------

    /** The plain crossfade length, used as the planner's fallback window. */
    val crossfadeSeconds = MutableStateFlow(0)

    /** The listener's own playback speed; a mix's tempo matching multiplies it. */
    val playbackSpeed = MutableStateFlow(1f)

    // ---- Published by the transition engine (read by the Dart UI) ---------

    /** True only while a transition that is actually *mixing* is audible. */
    val smartMixInProgress = MutableStateFlow(false)

    /** The blend in flight — its progress and the beat it runs on — or null. */
    val smartMixBlend = MutableStateFlow<MixBlend?>(null)

    /** The blend in flight laid out for the mix view, or null between blends. */
    val smartMixView = MutableStateFlow<MixTransitionView?>(null)

    /** How far through [smartMixView]'s blend playback is, 0..1. */
    val smartMixProgress = MutableStateFlow(0f)

    /** How much of the upcoming transition has been analysed. */
    val smartAnalysis = MutableStateFlow(SmartAnalysis())

    /** Automix's stats-for-nerds line, or null while Automix is off. */
    val automixDetail = MutableStateFlow<String?>(null)

    /** Where on the playing track the next transition is planned, or null. */
    val smartTransitionWindow = MutableStateFlow<TransitionWindow?>(null)

    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { prefs, _ ->
        read(prefs)
    }

    fun init(prefs: SharedPreferences) {
        read(prefs)
        prefs.registerOnSharedPreferenceChangeListener(listener)
    }

    private fun read(prefs: SharedPreferences) {
        smartFadeEnabled.value = prefs.getBoolean(KEY_AUTOMIX_ENABLED, false)
        automixPerformanceMode.value = runCatching {
            AutomixPerformanceMode.valueOf(
                prefs.getString(KEY_AUTOMIX_PERFORMANCE_MODE, null)
                    ?: AutomixPerformanceMode.BALANCED.name,
            )
        }.getOrDefault(AutomixPerformanceMode.BALANCED)
    }
}

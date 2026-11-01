package com.nirmal.inzx.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioDeviceInfo
import android.media.AudioManager
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Per-track loudness normalization gains, as BitChord computes them
 * (`PlaybackService.loudnessGainMb`): each song is brought to YouTube's
 * reference by minus its `loudnessDb` (the figure YouTube Music normalizes
 * with), in millibels clamped to [-15 dB, +3 dB].
 *
 * The figures come from Inzx's YouTube player responses, pushed by Dart with
 * the queue. BitChord's two settings, both on by default: normalization
 * itself, and skipping it on the phone's own speaker (where levelling down a
 * loud master mostly just makes it quieter).
 */
object LoudnessGains {
    const val KEY_ENABLED = "flutter.loudness_normalization"
    const val KEY_OFF_ON_SPEAKER = "flutter.loudness_off_on_speaker"
    private const val MIN_GAIN_MB = -1500
    private const val MAX_GAIN_MB = 300

    private val loudnessDb = ConcurrentHashMap<String, Double>()
    @Volatile private var prefs: SharedPreferences? = null
    @Volatile private var audioManager: AudioManager? = null

    fun init(context: Context, prefs: SharedPreferences) {
        this.prefs = prefs
        audioManager = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    fun update(figures: Map<String, Double>) {
        loudnessDb.putAll(figures)
    }

    val enabled: Boolean get() = prefs?.getBoolean(KEY_ENABLED, true) ?: true
    private val offOnSpeaker: Boolean get() = prefs?.getBoolean(KEY_OFF_ON_SPEAKER, true) ?: true

    /** Linear gain for [mediaId]; 1 when off, on the speaker, or unknown. */
    fun gainFor(mediaId: String): Float {
        val mb = gainMb(mediaId) ?: return 1f
        return 10.0.pow(mb / 2000.0).toFloat()
    }

    private fun gainMb(mediaId: String): Int? {
        if (!enabled) return null
        if (offOnSpeaker && onPhoneSpeaker()) return null
        val db = loudnessDb[mediaId] ?: return null
        return (-db * 100.0).roundToInt().coerceIn(MIN_GAIN_MB, MAX_GAIN_MB)
    }

    /** No headphones, Bluetooth, USB or HDMI output: the phone's own speaker. */
    private fun onPhoneSpeaker(): Boolean {
        val am = audioManager ?: return false
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).none {
            when (it.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_HDMI,
                AudioDeviceInfo.TYPE_LINE_ANALOG,
                AudioDeviceInfo.TYPE_LINE_DIGITAL -> true
                else -> false
            }
        }
    }
}

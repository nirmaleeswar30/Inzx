package com.nirmal.inzx.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioAttributes as PlatformAudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.media.AudioTrack
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.media3.common.AudioAttributes
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import com.music.bitchord.playback.LoudnessProcessor
import com.music.bitchord.playback.TransitionFilterProcessor
import com.music.bitchord.playback.audio.DspChain
import com.music.bitchord.playback.audio.PrecisionAudioSink
import com.music.bitchord.playback.audio.bitperfect.BitPerfectOutput

/**
 * How Inzx's audio leaves the app.
 *
 * - **Hi-Res output** (on by default): ExoPlayer's sink takes float PCM, so
 *   the FLAC decoder hands over 24-bit samples intact instead of being told
 *   to produce 16-bit (float32 holds every 24-bit sample exactly).
 * - **Extension decoders**: extension renderers are switched on, so an
 *   FFmpeg decoder (for ALAC and other formats the phone can't decode) is
 *   picked up automatically once one is bundled. None is yet: the published
 *   builds are GPL, which an MIT app can't ship without relicensing.
 * - **Bit-perfect USB DAC** (Android 14+, opt in): just before each audio
 *   track is created, the connected USB DAC's mixer is locked to that
 *   track's exact rate and encoding with Android's bit-perfect mixer
 *   behaviour, so samples reach the DAC unchanged. When the DAC can't take
 *   the track's format, playback falls back to the normal mixer and
 *   [status] says why.
 *
 * Settings are read from Flutter's shared preferences (written by the
 * Dart side), so a toggle applies from the next track without a restart.
 * Hi-Res output is fixed when a player is created, so it applies on the
 * next app start.
 */
object InzxAudioOutput {
    private const val TAG = "InzxAudioOutput"
    private const val PREFS = "FlutterSharedPreferences"
    const val KEY_HI_RES = "flutter.inzx_hires_output"
    const val KEY_BIT_PERFECT = "flutter.inzx_bitperfect_usb"

    @Volatile private var prefs: SharedPreferences? = null
    @Volatile private var appContext: Context? = null

    /** What happened to the most recent audio track. Read by the Signal path sheet. */
    @Volatile var status: Map<String, Any?> = emptyMap()
        private set

    fun init(context: Context) {
        appContext = context.applicationContext
        val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs = p
        InzxEqualizer.init(p)
        LoudnessGains.init(context, p)
    }

    val hiResOutput: Boolean get() = prefs?.getBoolean(KEY_HI_RES, true) ?: true
    val bitPerfectRequested: Boolean get() = prefs?.getBoolean(KEY_BIT_PERFECT, false) ?: false
    val bitPerfectSupported: Boolean get() = Build.VERSION.SDK_INT >= 34

    fun renderersFactory(context: Context): DefaultRenderersFactory = InzxRenderersFactory(context)

    /** The first connected USB audio output, if any. */
    fun usbOutput(audioManager: AudioManager): AudioDeviceInfo? =
        audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        }

    /** Info for the Dart side: capabilities, settings and the last track's path. */
    fun describe(): Map<String, Any?> {
        val ctx = appContext
        val usb = ctx?.let { usbOutput(it.getSystemService(Context.AUDIO_SERVICE) as AudioManager) }
        return mapOf(
            "bitPerfectSupported" to bitPerfectSupported,
            "bitPerfectRequested" to bitPerfectRequested,
            "hiResOutput" to hiResOutput,
            "usbDac" to usb?.productName?.toString(),
        ) + status
    }

    internal fun record(
        config: AudioSink.AudioTrackConfig,
        bitPerfect: Boolean,
        device: String?,
        reason: String?,
    ) {
        // Automix never mixes while bit-perfect output is active (BitChord's rule).
        BitPerfectOutput.setActive(bitPerfect)
        status = mapOf(
            "trackSampleRate" to config.sampleRate,
            "trackEncoding" to encodingName(config.encoding),
            "trackBitDepth" to bitDepth(config.encoding),
            "bitPerfectActive" to bitPerfect,
            "bitPerfectDevice" to device,
            "bitPerfectReason" to reason,
        )
        Log.i(TAG, "track ${config.sampleRate} Hz ${encodingName(config.encoding)} " +
            "bitPerfect=$bitPerfect device=$device reason=$reason")
    }

    fun encodingName(encoding: Int): String = when (encoding) {
        AudioFormat.ENCODING_PCM_16BIT -> "PCM 16-bit"
        AudioFormat.ENCODING_PCM_FLOAT -> "PCM float"
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> "PCM 24-bit"
        AudioFormat.ENCODING_PCM_32BIT -> "PCM 32-bit"
        AudioFormat.ENCODING_PCM_8BIT -> "PCM 8-bit"
        else -> "encoding $encoding"
    }

    private fun bitDepth(encoding: Int): Int? = when (encoding) {
        AudioFormat.ENCODING_PCM_16BIT -> 16
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> 24
        AudioFormat.ENCODING_PCM_32BIT, AudioFormat.ENCODING_PCM_FLOAT -> 32
        AudioFormat.ENCODING_PCM_8BIT -> 8
        else -> null
    }
}

/**
 * ExoPlayer renderers with Inzx's sink, one factory per player.
 *
 * The sink is BitChord's [PrecisionAudioSink] (Automix's transition filter
 * and loop mix, and loudness normalization, all in Float32 with exact
 * timestamps) forwarding to Media3's own sink, which keeps Inzx's equaliser,
 * hi-res float output and bit-perfect USB mode. Each factory owns its
 * player's DSP chain; the Automix engine finds it through the player
 * lifecycle hook.
 */
class InzxRenderersFactory(context: Context) : DefaultRenderersFactory(context) {
    /** This player's Automix filter (BitChord's, with its loop-mix port). */
    val transitionFilter = TransitionFilterProcessor()

    /** This player's loudness normalization (BitChord's), levelling its own song. */
    val loudness = LoudnessProcessor().apply { gainFor = LoudnessGains::gainFor }

    private val dspChain = DspChain(transition = transitionFilter, loudness = loudness)

    init {
        // Platform decoders first; an extension decoder (if bundled) only for
        // what they can't play.
        setExtensionRendererMode(EXTENSION_RENDERER_MODE_ON)
        setEnableAudioFloatOutput(InzxAudioOutput.hiResOutput)
    }

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioTrackPlaybackParams: Boolean,
    ): AudioSink {
        val delegate = DefaultAudioSink.Builder(context)
            .setEnableFloatOutput(enableFloatOutput)
            .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
            .setAudioTrackProvider(BitPerfectTrackProvider(context))
            // The equaliser, then the AutoEQ headphone correction (both stay
            // out of the chain while bit-perfect is on).
            .setAudioProcessors(arrayOf(EqualizerProcessor(), ParametricEqProcessor()))
            .build()
        return PrecisionAudioSink(
            delegate = delegate,
            dspChain = dspChain,
            enableFloatOutput = enableFloatOutput,
        )
    }
}

/**
 * Creates each AudioTrack, first pointing the USB DAC's mixer at the
 * track's exact format when bit-perfect output is on.
 */
private class BitPerfectTrackProvider(context: Context) : DefaultAudioSink.AudioTrackProvider {
    private val audioManager = context.applicationContext
        .getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun getAudioTrack(
        config: AudioSink.AudioTrackConfig,
        audioAttributes: AudioAttributes,
        audioSessionId: Int,
        context: Context?,
    ): AudioTrack {
        val platformAttributes = audioAttributes.platformAudioAttributes
        if (!InzxAudioOutput.bitPerfectSupported) {
            InzxAudioOutput.record(config, false, null, "Needs Android 14 or newer")
        } else {
            applyBitPerfect(config, platformAttributes)
        }
        return DefaultAudioSink.AudioTrackProvider.DEFAULT
            .getAudioTrack(config, audioAttributes, audioSessionId, context)
    }

    @RequiresApi(34)
    private fun applyBitPerfect(
        config: AudioSink.AudioTrackConfig,
        attributes: PlatformAudioAttributes,
    ) {
        val usb = InzxAudioOutput.usbOutput(audioManager)
        if (!InzxAudioOutput.bitPerfectRequested || usb == null) {
            // Leave the DAC to the normal mixer (and release it if we held it).
            usb?.let { runCatching { audioManager.clearPreferredMixerAttributes(attributes, it) } }
            InzxAudioOutput.record(
                config, false, usb?.productName?.toString(),
                when {
                    usb == null -> "No USB DAC connected"
                    else -> "Bit-perfect output is off"
                },
            )
            return
        }

        val name = usb.productName?.toString()
        if (config.offload || config.tunneling) {
            InzxAudioOutput.record(config, false, name, "Offloaded playback can't be bit-perfect")
            return
        }
        val match = runCatching { audioManager.getSupportedMixerAttributes(usb) }
            .getOrDefault(emptyList())
            .firstOrNull { it.matches(config) }
        if (match == null) {
            runCatching { audioManager.clearPreferredMixerAttributes(attributes, usb) }
            InzxAudioOutput.record(
                config, false, name,
                "DAC has no bit-perfect mode for ${config.sampleRate} Hz " +
                    InzxAudioOutput.encodingName(config.encoding),
            )
            return
        }
        val ok = runCatching { audioManager.setPreferredMixerAttributes(attributes, usb, match) }
            .getOrDefault(false)
        InzxAudioOutput.record(
            config, ok, name,
            if (ok) null else "Android refused the bit-perfect mixer",
        )
    }

    @RequiresApi(34)
    private fun AudioMixerAttributes.matches(config: AudioSink.AudioTrackConfig): Boolean {
        if (mixerBehavior != AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT) return false
        val f = format
        return f.sampleRate == config.sampleRate &&
            f.encoding == config.encoding &&
            f.channelMask == config.channelConfig
    }
}

package com.nirmal.inzx.audio

import android.content.SharedPreferences
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tanh

/**
 * The equaliser's settings, shared by every player's [EqualizerProcessor].
 *
 * Seven bands. The two ends are shelves, not bells: "more bass" should lift
 * everything below 60 Hz, not a hump around it, and the same for the top.
 * The middle five are bells with a Q of 1, wide enough to overlap so moving
 * neighbours together lifts a region evenly.
 *
 * Written by the Dart side to Flutter's shared preferences; changes are
 * picked up live through a preference listener.
 */
object InzxEqualizer {
    const val KEY_ENABLED = "flutter.inzx_eq_enabled"
    const val KEY_BANDS = "flutter.inzx_eq_bands"

    val BANDS_HZ = floatArrayOf(60f, 150f, 400f, 1_000f, 2_500f, 6_000f, 14_000f)
    const val BELL_Q = 1.0

    @Volatile var enabled = false
        private set
    @Volatile var gainsDb = FloatArray(BANDS_HZ.size)
        private set

    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { prefs, key ->
        if (key == KEY_ENABLED || key == KEY_BANDS) read(prefs)
    }

    fun init(prefs: SharedPreferences) {
        read(prefs)
        prefs.registerOnSharedPreferenceChangeListener(listener)
    }

    private fun read(prefs: SharedPreferences) {
        enabled = prefs.getBoolean(KEY_ENABLED, false)
        val parsed = prefs.getString(KEY_BANDS, null)
            ?.split(',')
            ?.mapNotNull { it.trim().toFloatOrNull() }
        gainsDb = FloatArray(BANDS_HZ.size) { i ->
            (parsed?.getOrNull(i) ?: 0f).coerceIn(-12f, 12f)
        }
    }

    /** What the processor should glide towards: the bands, or flat when off. */
    fun target(): FloatArray = if (enabled) gainsDb.copyOf() else FloatArray(BANDS_HZ.size)
}

/**
 * Applies [InzxEqualizer] to PCM in ExoPlayer's audio chain.
 *
 * Handles 16-bit and float PCM (float is what Hi-Res output feeds it). Gain
 * changes glide over ~70 ms instead of jumping, so dragging a slider or
 * switching preset never clicks. A flat, settled EQ copies samples through
 * untouched, and the processor stays out of the chain entirely while
 * bit-perfect output is requested.
 *
 * Boosts are paid for with a preamp of half the largest boost; the rare
 * peak that still goes over is rounded off by a soft limiter rather than
 * clipped.
 */
class EqualizerProcessor : BaseAudioProcessor() {
    private val bandCount = InzxEqualizer.BANDS_HZ.size
    private var channels = 0
    private var sampleRate = 0
    private var isFloat = false

    private val current = FloatArray(bandCount)
    private var preampDb = 0f

    // Coefficients per band: b0, b1, b2, a1, a2 (a0 normalised to 1).
    private val coeffs = Array(bandCount) { DoubleArray(5) }
    // Direct-form-I state per band per channel: x1, x2, y1, y2.
    private var state = Array(0) { DoubleArray(0) }

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat,
    ): AudioProcessor.AudioFormat {
        val supported = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT ||
            inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        if (!supported || inputAudioFormat.channelCount < 1 ||
            InzxAudioOutput.bitPerfectRequested
        ) {
            return AudioProcessor.AudioFormat.NOT_SET
        }
        channels = inputAudioFormat.channelCount
        sampleRate = inputAudioFormat.sampleRate
        isFloat = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        // Start where the settings are: no glide in from flat at track start.
        val target = InzxEqualizer.target()
        target.copyInto(current)
        state = Array(bandCount * channels) { DoubleArray(4) }
        for (b in 0 until bandCount) updateCoefficients(b)
        preampDb = preampFor(current)
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val bytesPerSample = if (isFloat) 4 else 2
        val frameBytes = bytesPerSample * channels
        val size = inputBuffer.remaining()
        if (size == 0) return
        val out = replaceOutputBuffer(size)
        val target = InzxEqualizer.target()

        if (isSettledFlat(target)) {
            out.put(inputBuffer) // bit-exact passthrough
            out.flip()
            return
        }

        inputBuffer.order(ByteOrder.nativeOrder())
        val frames = size / frameBytes
        var frame = 0
        while (frame < frames) {
            // Move gains toward the target once per block, then filter it.
            glide(target)
            val preamp = 10.0.pow(preampDb / 20.0)
            val blockEnd = minOf(frames, frame + GLIDE_FRAMES)
            while (frame < blockEnd) {
                for (ch in 0 until channels) {
                    var x = if (isFloat) {
                        inputBuffer.getFloat().toDouble()
                    } else {
                        inputBuffer.getShort() / 32768.0
                    }
                    x *= preamp
                    for (b in 0 until bandCount) {
                        if (abs(current[b]) < 0.01f) continue
                        x = biquad(b, ch, x)
                    }
                    val y = softLimit(x)
                    if (isFloat) {
                        out.putFloat(y.toFloat())
                    } else {
                        val s = (y * 32768.0).toLong().coerceIn(-32768L, 32767L)
                        out.putShort(s.toInt().toShort())
                    }
                }
                frame++
            }
        }
        out.flip()
    }

    private fun isSettledFlat(target: FloatArray): Boolean {
        for (b in 0 until bandCount) {
            if (abs(target[b]) >= 0.01f || abs(current[b]) >= 0.01f) return false
        }
        return true
    }

    private fun glide(target: FloatArray) {
        var changed = false
        for (b in 0 until bandCount) {
            val diff = target[b] - current[b]
            if (abs(diff) < 0.001f) continue
            val step = diff.coerceIn(-STEP_DB, STEP_DB)
            current[b] = if (abs(diff) <= STEP_DB) target[b] else current[b] + step
            updateCoefficients(b)
            changed = true
        }
        if (changed) preampDb = preampFor(current)
    }

    private fun preampFor(gains: FloatArray): Float {
        val maxBoost = gains.maxOrNull()?.coerceAtLeast(0f) ?: 0f
        return -maxBoost / 2f
    }

    private fun biquad(band: Int, ch: Int, x: Double): Double {
        val c = coeffs[band]
        val s = state[band * channels + ch]
        val y = c[0] * x + c[1] * s[0] + c[2] * s[1] - c[3] * s[2] - c[4] * s[3]
        s[1] = s[0]; s[0] = x
        s[3] = s[2]; s[2] = y
        return y
    }

    /** RBJ audio-EQ-cookbook peaking / shelving coefficients. */
    private fun updateCoefficients(band: Int) {
        val gainDb = current[band].toDouble()
        val freq = InzxEqualizer.BANDS_HZ[band].toDouble()
            .coerceAtMost(sampleRate * 0.45)
        val a = 10.0.pow(gainDb / 40.0)
        val w0 = 2.0 * PI * freq / sampleRate
        val cosW = cos(w0)
        val sinW = sin(w0)
        val c = coeffs[band]
        val (b0, b1, b2, a0, a1, a2) = when (band) {
            0 -> { // low shelf, slope 1
                val alpha = sinW / 2.0 * sqrt(2.0)
                val sq = 2.0 * sqrt(a) * alpha
                Six(
                    a * ((a + 1) - (a - 1) * cosW + sq),
                    2 * a * ((a - 1) - (a + 1) * cosW),
                    a * ((a + 1) - (a - 1) * cosW - sq),
                    (a + 1) + (a - 1) * cosW + sq,
                    -2 * ((a - 1) + (a + 1) * cosW),
                    (a + 1) + (a - 1) * cosW - sq,
                )
            }
            bandCount - 1 -> { // high shelf, slope 1
                val alpha = sinW / 2.0 * sqrt(2.0)
                val sq = 2.0 * sqrt(a) * alpha
                Six(
                    a * ((a + 1) + (a - 1) * cosW + sq),
                    -2 * a * ((a - 1) + (a + 1) * cosW),
                    a * ((a + 1) + (a - 1) * cosW - sq),
                    (a + 1) - (a - 1) * cosW + sq,
                    2 * ((a - 1) - (a + 1) * cosW),
                    (a + 1) - (a - 1) * cosW - sq,
                )
            }
            else -> { // bell
                val alpha = sinW / (2.0 * InzxEqualizer.BELL_Q)
                Six(
                    1 + alpha * a,
                    -2 * cosW,
                    1 - alpha * a,
                    1 + alpha / a,
                    -2 * cosW,
                    1 - alpha / a,
                )
            }
        }
        c[0] = b0 / a0; c[1] = b1 / a0; c[2] = b2 / a0
        c[3] = a1 / a0; c[4] = a2 / a0
    }

    /** Transparent below the knee; rounds peaks off towards full scale above it. */
    private fun softLimit(x: Double): Double {
        val m = abs(x)
        if (m <= KNEE) return x
        val over = (m - KNEE) / (1.0 - KNEE)
        val limited = KNEE + (1.0 - KNEE) * tanh(over)
        return if (x < 0) -limited else limited
    }

    override fun onFlush() {
        for (s in state) s.fill(0.0)
    }

    override fun onReset() {
        state = Array(0) { DoubleArray(0) }
        channels = 0
    }

    private data class Six(
        val b0: Double, val b1: Double, val b2: Double,
        val a0: Double, val a1: Double, val a2: Double,
    )

    private companion object {
        /** Frames between gain/coefficient steps: ~1.5 ms at 44.1 kHz. */
        const val GLIDE_FRAMES = 64
        /** Max gain change per step: ~12 dB takes ~70 ms. */
        const val STEP_DB = 0.25f
        const val KNEE = 0.95
    }
}

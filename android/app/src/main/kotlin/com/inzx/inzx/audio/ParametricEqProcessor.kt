package com.nirmal.inzx.audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import com.lastwave.app.playback.eq.ParametricEqNative
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Runs the AutoEQ correction (LastWave's AutoEqController, ported) on PCM in
 * ExoPlayer's audio chain: up to 20 biquads plus a preamp, computed with
 * LastWave's own filter formulas (PeqMath), so what plays is the curve the
 * AutoEQ screen draws.
 *
 * 16-bit and float PCM. Out of the chain while bit-perfect output is
 * requested; with no correction published, samples pass through untouched.
 * A new correction swaps coefficients at a buffer boundary and keeps the
 * filter state, so changing target or bass doesn't click.
 */
class ParametricEqProcessor : BaseAudioProcessor() {
    private var channels = 0
    private var sampleRate = 0
    private var isFloat = false

    private var seenVersion = -1
    private var active = false
    private var preamp = 1.0
    private var coeffs: Array<DoubleArray> = emptyArray() // b0 b1 b2 a1 a2
    private var state: Array<DoubleArray> = emptyArray()  // per filter*channel: x1 x2 y1 y2

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
        seenVersion = -1
        refresh()
        return inputAudioFormat
    }

    private fun refresh() {
        val version = ParametricEqNative.version
        if (version == seenVersion) return
        seenVersion = version
        val p = ParametricEqNative.published
        active = p.enabled && p.filters.any { it.enabled }
        preamp = 10.0.pow(p.preampDb / 20.0)
        val enabledFilters = p.filters.filter { it.enabled }
        val newCoeffs = Array(enabledFilters.size) { coefficients(enabledFilters[it]) }
        if (newCoeffs.size != coeffs.size) {
            state = Array(newCoeffs.size * channels) { DoubleArray(4) }
        }
        coeffs = newCoeffs
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        refresh()
        val size = inputBuffer.remaining()
        if (size == 0) return
        val out = replaceOutputBuffer(size)
        if (!active) {
            out.put(inputBuffer)
            out.flip()
            return
        }
        inputBuffer.order(ByteOrder.nativeOrder())
        val bytesPerSample = if (isFloat) 4 else 2
        val frames = size / (bytesPerSample * channels)
        val count = coeffs.size
        for (frame in 0 until frames) {
            for (ch in 0 until channels) {
                var x = if (isFloat) inputBuffer.getFloat().toDouble() else inputBuffer.getShort() / 32768.0
                x *= preamp
                for (f in 0 until count) {
                    val c = coeffs[f]
                    val s = state[f * channels + ch]
                    val y = c[0] * x + c[1] * s[0] + c[2] * s[1] - c[3] * s[2] - c[4] * s[3]
                    s[1] = s[0]; s[0] = x
                    s[3] = s[2]; s[2] = y
                    x = y
                }
                if (isFloat) {
                    out.putFloat(x.toFloat())
                } else {
                    out.putShort((x * 32768.0).toLong().coerceIn(-32768L, 32767L).toInt().toShort())
                }
            }
        }
        out.flip()
    }

    override fun onFlush() {
        for (s in state) s.fill(0.0)
    }

    override fun onReset() {
        state = emptyArray()
        coeffs = emptyArray()
        seenVersion = -1
    }

    /** LastWave's PeqMath coefficients (types: 0 peak, 1 low shelf, 2 high shelf, 3 LP, 4 HP). */
    private fun coefficients(filter: ParametricEqNative.NativeFilter): DoubleArray {
        val rate = sampleRate.toDouble()
        val f = filter.frequencyHz.toDouble().coerceIn(10.0, rate * 0.49)
        val w = 2.0 * PI * f / rate
        val cs = cos(w)
        val alpha = sin(w) / (2.0 * max(filter.q.toDouble(), 0.05))
        val a = 10.0.pow(filter.gainDb / 40.0)
        val b0: Double; val b1: Double; val b2: Double
        val a0: Double; val a1: Double; val a2: Double
        when (filter.type) {
            1 -> {
                val k = 2 * sqrt(a) * alpha
                b0 = a * ((a + 1) - (a - 1) * cs + k)
                b1 = 2 * a * ((a - 1) - (a + 1) * cs)
                b2 = a * ((a + 1) - (a - 1) * cs - k)
                a0 = (a + 1) + (a - 1) * cs + k
                a1 = -2 * ((a - 1) + (a + 1) * cs)
                a2 = (a + 1) + (a - 1) * cs - k
            }
            2 -> {
                val k = 2 * sqrt(a) * alpha
                b0 = a * ((a + 1) + (a - 1) * cs + k)
                b1 = -2 * a * ((a - 1) + (a + 1) * cs)
                b2 = a * ((a + 1) + (a - 1) * cs - k)
                a0 = (a + 1) - (a - 1) * cs + k
                a1 = 2 * ((a - 1) - (a + 1) * cs)
                a2 = (a + 1) - (a - 1) * cs - k
            }
            3 -> {
                b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = (1 - cs) / 2
                a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha
            }
            4 -> {
                b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = (1 + cs) / 2
                a0 = 1 + alpha; a1 = -2 * cs; a2 = 1 - alpha
            }
            else -> {
                b0 = 1 + alpha * a; b1 = -2 * cs; b2 = 1 - alpha * a
                a0 = 1 + alpha / a; a1 = -2 * cs; a2 = 1 - alpha / a
            }
        }
        return doubleArrayOf(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    }
}

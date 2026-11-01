package com.music.bitchord.playback.audio

import android.util.Log
import com.music.bitchord.BuildConfig
import com.music.bitchord.playback.LoudnessProcessor
import com.music.bitchord.playback.TransitionFilterProcessor

/**
 * Composite DSP chain executing BitChord's custom audio processors in their canonical sequence.
 *
 * Inzx port: BitChord runs SpatialAudioProcessor -> EqualizerProcessor ->
 * TransitionFilterProcessor -> LoudnessProcessor here. Inzx has no spatial
 * audio, and its own equaliser runs ahead of this sink (in the delegate's
 * processor chain), so this chain is the last two stages, in BitChord's order:
 *
 * AudioBlock(Float32) -> TransitionFilterProcessor -> LoudnessProcessor -> AudioBlock(Float32)
 *
 * Operates purely on in-place Float32 audio blocks without intermediate fixed-point quantization,
 * preserving full dynamic range and headroom.
 *
 * Loudness normalization is the last stage, and per sink on purpose: each
 * player levels the track *it* is playing, so the two sides of a crossfade are
 * each levelled for their own song — see [LoudnessProcessor]. Last because its
 * limiter has to see the signal every other stage has finished shaping.
 *
 * ## Staying out of the way
 *
 * Every stage here self-bypasses when its own setting is off, returning before
 * it reads a single sample rather than multiplying through by unity. With both
 * idle the block leaves this class byte-identical to how it arrived, which is
 * what lets [PcmBoundary]'s power-of-two scaling round-trip 16- and 24-bit
 * integers unchanged — see `PrecisionAudioSink.publishOutputExactness`.
 */
class DspChain(
    val transition: TransitionFilterProcessor = TransitionFilterProcessor(),
    val loudness: LoudnessProcessor = LoudnessProcessor(),
) : FloatAudioProcessor {

    private var currentSampleRate: Int = 0
    private var processCounter: Long = 0L

    override fun configure(sampleRate: Int, channelCount: Int) {
        this.currentSampleRate = sampleRate
        transition.configure(sampleRate, channelCount)
        loudness.configure(sampleRate, channelCount)
    }

    fun onStreamBoundary() {
        loudness.onStreamBoundary()
    }

    override fun process(block: AudioBlock) {
        if (block.frameCount == 0) return

        if (BuildConfig.DEBUG) {
            processCounter++
            if (processCounter == 1L || processCounter % 500L == 0L) {
                try {
                    Log.d(
                        TAG,
                        "process() #$processCounter frames=${block.frameCount} " +
                            "sr=$currentSampleRate transition=${transition.isFiltering}",
                    )
                } catch (_: Throwable) {
                }
            }
        }

        transition.process(block)
        loudness.process(block)
    }

    @Suppress("DEPRECATION")
    override fun flush() {
        transition.flush()
        loudness.flush()
    }

    override fun reset() {
        processCounter = 0L
        transition.reset()
        loudness.reset()
    }

    companion object {
        private const val TAG = "DspChain"
    }
}

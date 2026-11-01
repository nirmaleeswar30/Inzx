package com.nirmal.inzx.automix

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import com.music.bitchord.data.listentogether.ListenTogether
import com.music.bitchord.data.settings.AppSettings
import com.music.bitchord.data.settings.AutomixPerformanceMode
import com.music.bitchord.data.settings.CpuCores
import com.music.bitchord.data.settings.TrackAnalysisState
import com.music.bitchord.playback.smart.TrackAnalysis
import java.util.Locale
import kotlin.math.roundToInt
import com.music.bitchord.playback.AudioCache
import com.music.bitchord.playback.InzxQueue
import com.music.bitchord.playback.smart.TrackAnalyzer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Inzx's side of Automix (the engine itself is BitChord's, ported under
 * com.music.bitchord.*). Owns the analyzer and speaks to Dart over
 * `inzx/automix`:
 *
 *  - `registerAudio {videoId, path}` — a complete cached YouTube file the
 *    analyzer may read for that track.
 *  - `request {videoId, durationSeconds}` — queue analysis (cheap to repeat;
 *    already analysed / in flight / no audio yet are no-ops).
 *  - `analysis {videoId}` — what's known so far, for the planner's caller
 *    and stats for nerds.
 *  - `setInJam {inJam}` — Jams never mix, so analysis stops.
 *
 * And back to Dart: `needAudio {videoId}` when the analyzer wants a track
 * whose YouTube audio isn't cached yet.
 */
@OptIn(UnstableApi::class)
object AutomixBridge {
    private const val CHANNEL = "inzx/automix"

    @Volatile private var analyzer: TrackAnalyzer? = null
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    fun analyzer(context: Context): TrackAnalyzer =
        analyzer ?: synchronized(this) {
            analyzer ?: TrackAnalyzer(context.applicationContext, AudioCache()).also { analyzer = it }
        }

    fun attach(context: Context, messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        AudioCache.onNeedAudio = { videoId ->
            main.post { channel?.invokeMethod("needAudio", mapOf("videoId" to videoId)) }
        }
        AutomixEngine.attach(ch)
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "sync" -> {
                        @Suppress("UNCHECKED_CAST")
                        val raw = call.argument<List<Map<String, Any?>>>("queue").orEmpty()
                        val entries = raw.map { e ->
                            InzxQueue.Entry(
                                id = e["id"] as String,
                                title = e["title"] as? String ?: "",
                                artist = e["artist"] as? String ?: "",
                                durationMs = (e["durationMs"] as? Number)?.toLong() ?: 0L,
                                artworkUrl = e["artwork"] as? String,
                                isVideo = e["video"] == true,
                            )
                        }
                        AutomixEngine.sync(
                            primaryId = call.argument<String>("primary")!!,
                            secondaryId = call.argument<String>("secondary")!!,
                            activePlayerId = call.argument<String>("active")!!,
                            currentIndex = call.argument<Int>("index") ?: -1,
                            entries = entries,
                            repeatMode = AutomixEngine.repeatModeFor(call.argument<String>("repeat")),
                            speed = (call.argument<Double>("speed") ?: 1.0).toFloat(),
                            crossfadeSeconds = call.argument<Int>("crossfadeSeconds") ?: 0,
                            loudnessDb = call.argument<Map<String, Double>>("loudness").orEmpty(),
                        )
                        result.success(null)
                    }
                    "loaded" -> {
                        AutomixEngine.loaded(
                            call.argument<String>("playerId")!!,
                            call.argument<Int>("index") ?: -1,
                        )
                        result.success(null)
                    }
                    "busy" -> {
                        AutomixEngine.setBusy(call.argument<Boolean>("busy") == true)
                        result.success(null)
                    }
                    "skip" -> {
                        AutomixEngine.onSkipRequested()
                        result.success(null)
                    }
                    "transitioning" -> result.success(AutomixEngine.isTransitioning())
                    "mixState" -> result.success(mixState())
                    "threads" -> result.success(
                        AutomixPerformanceMode.entries.associate { it.name to it.inferenceThreads } +
                            mapOf("cores" to CpuCores.total, "fastCores" to CpuCores.fast),
                    )
                    "registerAudio" -> {
                        val id = call.argument<String>("videoId")
                        val path = call.argument<String>("path")
                        if (id != null && path != null) AudioCache.register(id, path)
                        result.success(null)
                    }
                    "request" -> {
                        val id = call.argument<String>("videoId")
                        val seconds = call.argument<Double>("durationSeconds") ?: 0.0
                        if (id != null) {
                            analyzer(context).request(id, AudioCache.uriFor(id), seconds)
                        }
                        result.success(null)
                    }
                    "analysis" -> {
                        val id = call.argument<String>("videoId")
                        result.success(id?.let { describe(context, it) })
                    }
                    "statsLine" -> {
                        result.success(
                            statsLine(
                                context,
                                call.argument<String>("current"),
                                call.argument<String>("next"),
                            ),
                        )
                    }
                    "setInJam" -> {
                        ListenTogether.setInJam(call.argument<Boolean>("inJam") == true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("AUTOMIX", e.message, null)
            }
        }
    }

    /**
     * Automix's stats-for-nerds line while it waits on analysis — BitChord's
     * `CrossfadeController.describeAutomix` waiting stage, verbatim in
     * wording: each side's state, and for an analysed side the tempo, key
     * and grid it will mix on (the tail for the playing song, the head for
     * the next). Null while Automix is off or in a Jam.
     */
    fun statsLine(context: Context, current: String?, next: String?): String? {
        if (!AppSettings.smartFadeEnabled.value || current == null) return null
        if (ListenTogether.state.value.inParty) return null
        // Once the engine runs, its own line (BitChord's, every stage
        // including the planned mix) is the one to show.
        AppSettings.automixDetail.value?.let { return it }
        val a = analyzer(context)
        fun label(id: String?, outgoing: Boolean): String {
            if (id == null) return "none"
            val analysis = a.analysisFor(id)
            val state = stateOf(a, id, analysis)
            if (state == TrackAnalysisState.ANALYSING) return "analysing…"
            if (state == TrackAnalysisState.WAITING) return "waiting"
            if (state == TrackAnalysisState.FAILED || !analysis.isUsable) return "failed"
            val side = if (outgoing) analysis.tailBeats else analysis.headBeats
            val bpm = side?.bpm ?: analysis.bpm
            val confidence = side?.confidence ?: analysis.beatConfidence
            val key = analysis.key.takeIf { it.isNotBlank() }?.let { " $it" }.orEmpty()
            val grid = if (side != null) "model grid" else "dsp grid"
            val refining = if (state == TrackAnalysisState.REFINING) ", refining" else ""
            return "analysed (${bpm.roundToInt()} BPM$key, $grid " +
                "${"%.2f".format(Locale.ROOT, confidence)}$refining)"
        }
        return "Automix · this song: ${label(current, true)} · next: ${label(next, false)}"
    }

    /**
     * What the engine publishes for the player UI (BitChord reads the same
     * fields in draw): whether a real mix is audible, how far through it is,
     * where the next one sits on the seek bar, and the blend's beat — the
     * time since a beat landed, so the animation can pulse on it.
     */
    private fun mixState(): Map<String, Any?> {
        val window = AppSettings.smartTransitionWindow.value
        val blend = AppSettings.smartMixBlend.value
        return mapOf(
            "mixing" to AppSettings.smartMixInProgress.value,
            "progress" to AppSettings.smartMixProgress.value.toDouble(),
            "windowStart" to window?.start?.toDouble(),
            "windowEnd" to window?.end?.toDouble(),
            "beatMs" to blend?.beatMs?.toDouble(),
            "sinceBeatMs" to blend?.let { (System.nanoTime() - it.beatAnchorNanos) / 1e6 },
            "blendPlaying" to blend?.playing,
        )
    }

    /** BitChord's `CrossfadeController.stateOf`. */
    private fun stateOf(a: TrackAnalyzer, id: String, analysis: TrackAnalysis): TrackAnalysisState =
        when {
            analysis.isUsable ->
                if (a.isAnalysing(id)) TrackAnalysisState.REFINING else TrackAnalysisState.ANALYSED
            a.isAnalysing(id) -> TrackAnalysisState.ANALYSING
            a.isAnalysed(id) -> TrackAnalysisState.FAILED
            else -> TrackAnalysisState.WAITING
        }

    private fun describe(context: Context, videoId: String): Map<String, Any?> {
        val a = analyzer(context)
        val analysis = a.analysisFor(videoId)
        return mapOf(
            "analysed" to a.isAnalysed(videoId),
            "analysing" to a.isAnalysing(videoId),
            "hasAudio" to AudioCache.has(videoId),
            "usable" to analysis.isUsable,
            "bpm" to analysis.bpm,
            "beatConfidence" to analysis.beatConfidence,
            "key" to analysis.key,
            "keyConfidence" to analysis.keyConfidence,
            "duration" to analysis.duration,
            "contentEnd" to analysis.contentEndTime,
            "mixIn" to analysis.mixInTime,
            "mixOut" to analysis.mixOutTime,
            "downbeats" to analysis.downbeats.size,
            "vocalProbability" to analysis.vocalProbability,
            "modelGrid" to (analysis.headBeats != null || analysis.tailBeats != null),
        )
    }
}

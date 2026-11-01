package com.nirmal.inzx.automix

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.RenderersFactory
import com.music.bitchord.data.settings.AppSettings
import com.music.bitchord.playback.AudioCache
import com.music.bitchord.playback.CrossfadeController
import com.music.bitchord.playback.DeckHost
import com.music.bitchord.playback.InzxDeck
import com.music.bitchord.playback.InzxQueue
import com.music.bitchord.playback.TransitionFilters
import com.nirmal.inzx.audio.InzxRenderersFactory
import com.nirmal.inzx.audio.LoudnessGains
import com.ryanheise.just_audio.JustAudioHooks
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.MainScope

/**
 * Hosts BitChord's [CrossfadeController] — the Automix transition engine,
 * ported unchanged — on Inzx's two just_audio players.
 *
 * The controller drives the players itself (volume, tempo, the filters riding
 * each side, when the incoming track starts) and asks the Inzx side for the
 * three things only Dart can do, over `inzx/automix`:
 *
 *  - `load {playerId, index, cueMs}` — put queue entry [index] on that player
 *    at the cue (Dart answers `loaded`).
 *  - `handoff {from, to, index}` — the blend's midpoint: the incoming player
 *    is now the song (Dart swaps its active player and moves the queue on).
 *  - `retire {playerId}` — the outgoing player is done; Dart stops it.
 *  - `playState {playerId, playing}` — the controller started/paused a player.
 *
 * Dart keeps the engine's picture current with `sync` (players, queue, which
 * player is active) and `busy` (a lossless/JioSaavn hand-over in flight, which
 * the controller waits out exactly as BitChord's waits out a version swap).
 */
@OptIn(UnstableApi::class)
object AutomixEngine : DeckHost, JustAudioHooks.PlayerLifecycle {
    private const val TAG = "AutomixEngine"

    override val queue = InzxQueue()

    private val decks = HashMap<String, InzxDeck>()
    private var activeId: String? = null
    private var standbyId: String? = null
    @Volatile private var dartBusy = false

    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var controller: CrossfadeController? = null
    private val scope = MainScope()
    private val main = Handler(Looper.getMainLooper())

    private fun deck(id: String): InzxDeck = decks.getOrPut(id) { InzxDeck(id, this) }

    fun init(context: Context) {
        this.context = context.applicationContext
        JustAudioHooks.playerLifecycle = this
    }

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    // ---- just_audio's ExoPlayers ------------------------------------------

    override fun created(playerId: String, player: ExoPlayer, factory: RenderersFactory?) {
        val inzx = factory as? InzxRenderersFactory
        runOnMain { deck(playerId).bind(player, inzx?.transitionFilter, inzx?.loudness) }
    }

    override fun released(playerId: String) {
        runOnMain {
            val d = decks[playerId] ?: return@runOnMain
            d.exo?.let(d::unbind)
        }
    }

    // ---- Dart -> engine -----------------------------------------------------

    /**
     * The players, the queue and which player is the song. Sent on every
     * track change, queue edit and swap Dart makes itself.
     */
    fun sync(
        primaryId: String,
        secondaryId: String,
        activePlayerId: String,
        currentIndex: Int,
        entries: List<InzxQueue.Entry>,
        repeatMode: Int,
        speed: Float,
        crossfadeSeconds: Int,
        loudnessDb: Map<String, Double> = emptyMap(),
    ) {
        queue.update(entries, repeatMode)
        LoudnessGains.update(loudnessDb)
        AppSettings.playbackSpeed.value = speed
        AppSettings.crossfadeSeconds.value = crossfadeSeconds
        val swapped = activeId != null && activeId != activePlayerId
        activeId = activePlayerId
        standbyId = if (activePlayerId == primaryId) secondaryId else primaryId
        val active = deck(activePlayerId)
        val transitioning = controller?.isTransitioning() == true
        // Dart moved the song itself (a tap, a skip, its own swap): the deck
        // that is the session holds Dart's current entry.
        if (!transitioning) {
            active.itemIndex = currentIndex
            // The session player levels the song it is playing (BitChord's
            // setupLoudness on every track change); the next id lets it follow
            // a gapless boundary on its own.
            val nextIndex = queue.nextIndex(currentIndex)
            active.loudness?.track(
                queue.entries.getOrNull(currentIndex)?.id,
                queue.entries.getOrNull(nextIndex)?.id,
            )
        }
        // A swap Inzx made itself (a lossless hand-over) moved the session to
        // the other player outside any blend: re-point the controller's
        // listener at it, as its own handoff does.
        if (swapped && !transitioning) controller?.start()
        ensureController()
    }

    fun loaded(playerId: String, index: Int) {
        decks[playerId]?.onLoaded(index)
    }

    fun setBusy(busy: Boolean) {
        dartBusy = busy
    }

    /** The listener asked for another song: drop any blend in flight first. */
    fun onSkipRequested() {
        controller?.onSkipRequested()
    }

    fun isTransitioning(): Boolean = controller?.isTransitioning() == true

    // ---- Engine -> Dart -----------------------------------------------------

    override fun load(deck: InzxDeck, index: Int, cueMs: Long) {
        call("load", mapOf("playerId" to deck.playerId, "index" to index, "cueMs" to cueMs))
    }

    override fun retire(deck: InzxDeck) {
        call("retire", mapOf("playerId" to deck.playerId))
    }

    override fun playStateChanged(deck: InzxDeck, playing: Boolean) {
        call("playState", mapOf("playerId" to deck.playerId, "playing" to playing))
    }

    private fun handoff(outgoing: InzxDeck, incoming: InzxDeck) {
        activeId = incoming.playerId
        standbyId = outgoing.playerId
        call(
            "handoff",
            mapOf(
                "from" to outgoing.playerId,
                "to" to incoming.playerId,
                "index" to incoming.itemIndex,
            ),
        )
    }

    private fun call(method: String, args: Map<String, Any?>) {
        runOnMain { channel?.invokeMethod(method, args) }
    }

    // ---- The controller -----------------------------------------------------

    private fun ensureController() {
        if (controller != null) return
        val ctx = context ?: return
        if (activeId == null || standbyId == null) return
        val analyzer = AutomixBridge.analyzer(ctx)
        val c = CrossfadeController(
            scope = scope,
            active = { deck(requireNotNull(activeId)) },
            standby = { deck(requireNotNull(standbyId)) },
            onHandoff = ::handoff,
            analysisFor = { item -> analyzer.analysisFor(item.mediaId) },
            requestAnalysis = { item, durationMs ->
                analyzer.request(item.mediaId, AudioCache.uriFor(item.mediaId), durationMs / 1000.0)
            },
            filters = object : TransitionFilters {
                // BitChord's mapping: "incoming" rides the session player's
                // filter, "outgoing" the spare's; both swap with the players
                // at the handoff, as the decks do here.
                private fun activeFilter() = activeId?.let { decks[it]?.filter }
                private fun spareFilter() = standbyId?.let { decks[it]?.filter }

                override fun incoming(lowPassHz: Float, highPassHz: Float) {
                    activeFilter()?.setCutoffs(lowPassHz, highPassHz)
                }

                override fun outgoing(lowPassHz: Float, highPassHz: Float) {
                    spareFilter()?.setCutoffs(lowPassHz, highPassHz)
                }

                override fun incomingLeadMs(): Long = (activeFilter()?.leadUs ?: 0L) / 1000

                override fun outgoingLeadMs(): Long = (spareFilter()?.leadUs ?: 0L) / 1000

                override fun incomingEcho(delaySeconds: Float, send: Float, dry: Float) {
                    activeFilter()?.setEcho(delaySeconds, send, dry)
                }

                override fun outgoingEcho(delaySeconds: Float, send: Float, dry: Float) {
                    spareFilter()?.setEcho(delaySeconds, send, dry)
                }

                override fun parkEchoes() {
                    decks.values.forEach { it.filter?.parkEcho() }
                }
            },
            analysisRunningFor = { item -> analyzer.isAnalysing(item.mediaId) },
            // BitChord: the spare's loudness is told which song it is about to
            // level before that player renders a frame.
            onArmIncoming = { item, nextId ->
                standbyId?.let { decks[it] }?.loudness?.track(item.mediaId, nextId)
            },
            onBlendHeadroom = { trim ->
                decks.values.forEach { it.loudness?.setBlendTrim(trim) }
            },
            loudnessGain = LoudnessGains::gainFor,
            versionSwapActive = { dartBusy },
            mixWaveform = { item, durationMs, from, to, bins ->
                analyzer.mixWaveform(
                    item.mediaId, AudioCache.uriFor(item.mediaId), durationMs / 1000.0, from, to, bins,
                )
            },
            loopPortOf = { d -> d.filter?.loop },
            loopRegion = { item, durationMs, from, to, rate ->
                analyzer.loopRegion(
                    item.mediaId, AudioCache.uriFor(item.mediaId), durationMs / 1000.0, from, to, rate,
                )
            },
        )
        controller = c
        c.start()
        Log.d(TAG, "Automix engine started")
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }

    /** Media3 repeat mode for Dart's loop mode name. */
    fun repeatModeFor(name: String?): Int = when (name) {
        "one" -> Player.REPEAT_MODE_ONE
        "all" -> Player.REPEAT_MODE_ALL
        else -> Player.REPEAT_MODE_OFF
    }
}

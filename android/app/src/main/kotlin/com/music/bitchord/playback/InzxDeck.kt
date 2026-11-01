/*
 * Inzx: one of the two players BitChord's CrossfadeController drives, as seen
 * from Inzx's architecture. Written for the Inzx port of BitChord's Automix.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 */

package com.music.bitchord.playback

import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

/**
 * In BitChord each of the two players is an ExoPlayer that owns the whole
 * queue. In Inzx the queue lives in Dart and each player (a just_audio
 * player) holds one song at a time, and its native ExoPlayer is released
 * whenever the Dart side stops it and rebuilt on the next load.
 *
 * So a deck is the stable thing the controller holds — one per just_audio
 * player id — exposing exactly the player members the controller uses:
 *
 *  - Playback (position, volume, speed, play state, end-of-item hold,
 *    listeners) goes straight to whichever ExoPlayer currently exists for the
 *    id; anything set while none does is kept and applied when one appears.
 *  - The queue (current/next item, item count, repeat mode) is answered from
 *    the queue Dart pushes ([DeckHost.queue]).
 *  - Loading a song ([setMediaItems]) asks Dart to load that queue entry onto
 *    this player at the cue point; the deck reads as buffering until Dart
 *    reports it loaded *and* the ExoPlayer is ready.
 *  - Retiring it ([stop] / [clearMediaItems]) asks Dart to stop the player,
 *    so just_audio's own state stays in step.
 */
@UnstableApi
class InzxDeck(val playerId: String, private val host: DeckHost) {

    /** The ExoPlayer just_audio has built for [playerId], if any right now. */
    var exo: ExoPlayer? = null
        private set

    /** This player's transition filter (and loop-mix port), with the ExoPlayer. */
    var filter: TransitionFilterProcessor? = null
        private set

    /** This player's loudness normalization, with the ExoPlayer. */
    var loudness: LoudnessProcessor? = null
        private set

    /** The queue index of the song this deck holds, or [C.INDEX_UNSET]. */
    @Volatile var itemIndex: Int = C.INDEX_UNSET

    /** A load Dart hasn't confirmed yet. */
    @Volatile private var loadingIndex: Int = C.INDEX_UNSET

    private val listeners = mutableListOf<Player.Listener>()
    private var wantedVolume = 1f
    private var wantedSpeed: Float? = null
    private var wantedPauseAtEnd = false

    fun bind(
        player: ExoPlayer,
        filter: TransitionFilterProcessor?,
        loudness: LoudnessProcessor?,
    ) {
        if (exo === player) return
        exo?.let { old -> listeners.forEach(old::removeListener) }
        exo = player
        this.filter = filter
        this.loudness = loudness
        listeners.forEach(player::addListener)
        player.volume = wantedVolume
        wantedSpeed?.let(player::setPlaybackSpeed)
        player.pauseAtEndOfMediaItems = wantedPauseAtEnd
    }

    fun unbind(player: ExoPlayer) {
        if (exo !== player) return
        listeners.forEach(player::removeListener)
        exo = null
        filter = null
        loudness = null
    }

    /**
     * Dart finished loading [index] onto this player. just_audio pushes its
     * own Dart-side volume and speed when it activates a player, so the
     * controller's (silent, tempo-matched) values are put back on top.
     */
    fun onLoaded(index: Int) {
        if (index == loadingIndex) loadingIndex = C.INDEX_UNSET
        exo?.let { player ->
            player.volume = wantedVolume
            wantedSpeed?.let(player::setPlaybackSpeed)
            player.pauseAtEndOfMediaItems = wantedPauseAtEnd
        }
    }

    private val loading: Boolean get() = loadingIndex != C.INDEX_UNSET

    // ---- Playback: straight to the ExoPlayer -----------------------------

    val currentPosition: Long get() = exo?.currentPosition ?: 0L

    val duration: Long
        get() = if (loading) C.TIME_UNSET else exo?.duration ?: C.TIME_UNSET

    val isPlaying: Boolean get() = !loading && exo?.isPlaying == true

    val playbackState: Int
        get() = when {
            loading -> Player.STATE_BUFFERING
            else -> exo?.playbackState ?: Player.STATE_IDLE
        }

    var volume: Float
        get() = exo?.volume ?: wantedVolume
        set(value) {
            wantedVolume = value
            exo?.volume = value
        }

    val playbackParameters: PlaybackParameters
        get() = exo?.playbackParameters ?: PlaybackParameters.DEFAULT

    fun setPlaybackSpeed(speed: Float) {
        wantedSpeed = speed
        exo?.setPlaybackSpeed(speed)
    }

    var playWhenReady: Boolean
        get() = exo?.playWhenReady ?: false
        set(value) {
            val player = exo ?: return
            if (player.playWhenReady == value) return
            player.playWhenReady = value
            host.playStateChanged(this, value)
        }

    fun play() {
        playWhenReady = true
    }

    fun pause() {
        playWhenReady = false
    }

    var pauseAtEndOfMediaItems: Boolean
        get() = exo?.pauseAtEndOfMediaItems ?: wantedPauseAtEnd
        set(value) {
            wantedPauseAtEnd = value
            exo?.pauseAtEndOfMediaItems = value
        }

    var skipSilenceEnabled: Boolean
        get() = exo?.skipSilenceEnabled ?: false
        set(value) {
            exo?.skipSilenceEnabled = value
        }

    fun seekTo(positionMs: Long) {
        exo?.seekTo(positionMs)
    }

    fun addListener(listener: Player.Listener) {
        if (listener in listeners) return
        listeners += listener
        exo?.addListener(listener)
    }

    fun removeListener(listener: Player.Listener) {
        listeners -= listener
        exo?.removeListener(listener)
    }

    // ---- Queue: answered from Dart's queue ---------------------------------

    val currentMediaItemIndex: Int get() = itemIndex

    val currentMediaItem: MediaItem? get() = host.queue.itemAt(itemIndex)

    val mediaItemCount: Int get() = host.queue.size

    fun getMediaItemAt(index: Int): MediaItem = host.queue.itemAt(index) ?: MediaItem.EMPTY

    val nextMediaItemIndex: Int get() = host.queue.nextIndex(itemIndex)

    fun hasNextMediaItem(): Boolean = nextMediaItemIndex != C.INDEX_UNSET

    /** No per-player timeline in Inzx; the controller falls back to queued durations. */
    val currentTimeline: Timeline get() = Timeline.EMPTY

    /** Dart's loop mode. Setting it is a no-op: both decks read the one queue. */
    var repeatMode: Int
        get() = host.queue.repeatMode
        set(@Suppress("UNUSED_PARAMETER") value) = Unit

    /** Dart's queue is already in play order, shuffle included. */
    var shuffleModeEnabled: Boolean
        get() = false
        set(@Suppress("UNUSED_PARAMETER") value) = Unit

    /**
     * The arm: load [startIndex] onto this player at [startPositionMs]. Dart
     * resolves and loads it (lossless copy included, when there is one) and
     * calls back through [onLoaded].
     */
    fun setMediaItems(items: List<MediaItem>, startIndex: Int, startPositionMs: Long) {
        itemIndex = startIndex
        loadingIndex = startIndex
        host.load(this, startIndex, startPositionMs)
    }

    /** Dart's load prepares the player itself. */
    fun prepare() = Unit

    /** Both decks read the same queue, so there's nothing to copy across. */
    fun addMediaItems(@Suppress("UNUSED_PARAMETER") items: List<MediaItem>) = Unit

    fun removeMediaItems(
        @Suppress("UNUSED_PARAMETER") fromIndex: Int,
        @Suppress("UNUSED_PARAMETER") toIndex: Int,
    ) = Unit

    /** Retired: Dart stops the player (which keeps just_audio's state in step). */
    fun stop() {
        loadingIndex = C.INDEX_UNSET
        host.retire(this)
    }

    fun clearMediaItems() = stop()
}

/** What a deck needs from the Inzx side. */
@UnstableApi
interface DeckHost {
    val queue: InzxQueue
    fun load(deck: InzxDeck, index: Int, cueMs: Long)
    fun retire(deck: InzxDeck)
    fun playStateChanged(deck: InzxDeck, playing: Boolean)
}

/**
 * Dart's queue as the decks see it: entries in play order, and the loop mode
 * as a Media3 repeat mode.
 */
class InzxQueue {
    data class Entry(
        val id: String,
        val title: String,
        val artist: String,
        val durationMs: Long,
        val artworkUrl: String?,
        val isVideo: Boolean,
    )

    @Volatile var entries: List<Entry> = emptyList()
        private set
    @Volatile var repeatMode: Int = Player.REPEAT_MODE_OFF

    private var items: List<MediaItem> = emptyList()

    val size: Int get() = entries.size

    fun update(entries: List<Entry>, repeatMode: Int) {
        this.entries = entries
        this.repeatMode = repeatMode
        items = entries.map { it.toMediaItem() }
    }

    fun itemAt(index: Int): MediaItem? = items.getOrNull(index)

    /** Media3's own next-index rule for a queue in play order. */
    fun nextIndex(index: Int): Int {
        if (index == C.INDEX_UNSET || entries.isEmpty()) return C.INDEX_UNSET
        return when {
            repeatMode == Player.REPEAT_MODE_ONE -> index
            index + 1 < entries.size -> index + 1
            repeatMode == Player.REPEAT_MODE_ALL -> 0
            else -> C.INDEX_UNSET
        }
    }

    private fun Entry.toMediaItem(): MediaItem = MediaItem.Builder()
        .setMediaId(id)
        // BitChord's queued items carry their length as `d` (seconds), which
        // the controller reads when no timeline has measured them yet.
        .setUri("bitchord://watch?v=$id&d=${(durationMs / 1000).coerceAtLeast(0)}" +
            if (isVideo) "&video=1" else "")
        .setMediaMetadata(
            androidx.media3.common.MediaMetadata.Builder()
                .setTitle(title)
                .setArtist(artist)
                .setArtworkUri(artworkUrl?.let(android.net.Uri::parse))
                .build(),
        )
        .build()
}

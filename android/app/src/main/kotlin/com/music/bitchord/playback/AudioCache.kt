/*
 * Inzx stand-in for BitChord's AudioCache, covering only what Automix's
 * TrackAnalyzer reads from it. Same names and shapes as BitChord's, so the
 * ported analyzer compiles unchanged; the answers come from Inzx's own
 * stream cache instead.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 */

package com.music.bitchord.playback

import android.media.MediaDataSource
import android.net.Uri
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.ConcurrentHashMap

/**
 * Inzx keeps whole-track YouTube audio files in its stream cache (the player
 * pre-downloads the next tracks, and finished downloads are renamed into
 * place, so a file that exists is complete). The Dart side registers each one
 * here by video id ([register]); the analyzer then reads it as the track's
 * single, complete "rendition".
 *
 * When a track has no file yet, [requestAnalysisHead] asks the Dart side to
 * download it — the same "fetch something to analyse" BitChord's cache does.
 */
class AudioCache {

    data class Rendition(val key: String, val contentLength: Long, val cachedPrefix: Long) {
        val isComplete: Boolean get() = contentLength > 0 && cachedPrefix >= contentLength
    }

    fun renditionsOf(uri: Uri): List<Rendition> {
        val id = cacheKeyOf(uri)
        val file = files[id]?.takeIf { it.isFile } ?: return emptyList()
        val length = file.length()
        if (length <= 0L) return emptyList()
        return listOf(Rendition(key = id, contentLength = length, cachedPrefix = length))
    }

    /**
     * Non-null like BitChord's: a rendition only exists once its file does,
     * and a file deleted since throws here, which the analyzer's pass
     * catches and records like any other failed decode.
     */
    fun renditionDataSource(uri: Uri, rendition: Rendition): MediaDataSource {
        val file = files[rendition.key] ?: error("No cached audio for ${rendition.key}")
        return FileMediaDataSource(file)
    }

    /** The YouTube video id: Inzx keys analysis by it. */
    fun cacheKeyOf(uri: Uri): String = uri.getQueryParameter("v") ?: uri.toString()

    fun requestAnalysisHead(uri: Uri) {
        val id = cacheKeyOf(uri)
        if (files.containsKey(id)) return
        if (requested.add(id)) onNeedAudio?.invoke(id)
    }

    /** A file that decoded short is forgotten so a fresh download can replace it. */
    fun discardBadRendition(uri: Uri, key: String): Boolean {
        files.remove(key)
        requested.remove(key)
        return true
    }

    companion object {
        private val files = ConcurrentHashMap<String, File>()
        private val requested = ConcurrentHashMap.newKeySet<String>()

        /** Set by the Dart bridge: download the YouTube audio for this video id. */
        @Volatile var onNeedAudio: ((String) -> Unit)? = null

        fun register(videoId: String, path: String) {
            files[videoId] = File(path)
            requested.remove(videoId)
        }

        fun has(videoId: String): Boolean = files[videoId]?.isFile == true

        /** BitChord's playback URI shape, which the analyzer reads `v` from. */
        fun uriFor(videoId: String): Uri = Uri.parse("bitchord://watch?v=$videoId")
    }
}

/** A plain file as a [MediaDataSource], for MediaExtractor. */
class FileMediaDataSource(file: File) : MediaDataSource() {
    private val raf = RandomAccessFile(file, "r")
    private val length = raf.length()

    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (position >= length) return -1
        synchronized(raf) {
            raf.seek(position)
            return raf.read(buffer, offset, size)
        }
    }

    override fun getSize(): Long = length

    override fun close() = raf.close()
}

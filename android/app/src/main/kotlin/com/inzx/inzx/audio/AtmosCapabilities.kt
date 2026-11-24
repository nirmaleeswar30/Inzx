package com.nirmal.inzx.audio

import android.media.MediaCodecList
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaFormat
import android.os.Build
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil

/** Native Atmos needs a JOC decoder and a spatial output. An E-AC-3 decoder
 * alone can play the surround core. */
internal object AtmosCapabilities {
    private val playbackAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
    val canDecodeJoc: Boolean by lazy {
        val mime = MediaFormat.MIMETYPE_AUDIO_EAC3_JOC
        runCatching {
            MediaCodecUtil.getDecoderInfos(mime, false, false).isNotEmpty()
        }.getOrElse {
            runCatching {
                MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
                    !info.isEncoder && info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
                }
            }.getOrDefault(false)
        }
    }

    fun isSpatialRoute(manager: AudioManager): Boolean {
        // Older Dolby devices can decode JOC without the Android Spatializer API.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S_V2) return canDecodeJoc
        return runCatching {
            val spatializer = manager.spatializer
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_5POINT1)
                .setSampleRate(48000)
                .build()
            spatializer.isAvailable && spatializer.isEnabled &&
                spatializer.canBeSpatialized(playbackAttributes, format)
        }.getOrDefault(false)
    }

}
